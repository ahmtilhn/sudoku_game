export interface CompetitiveEconomyHardeningEnv {
  DB: D1Database;
}

let installation: Promise<void> | null = null;

const ACTIVE_STATUSES = "'waiting', 'ready_window', 'countdown', 'active', 'paused'";
const TERMINAL_RATED_STATUSES = "'completed', 'forfeited', 'abandoned'";
const MAX_RATED_PAIR_MATCHES_24H = 3;

/**
 * Runtime safety net for the competitive Coin/MMR boundary.
 *
 * Migrations remain canonical. This installer exists because production can
 * briefly run a new Worker before a D1 migration has propagated. It also keeps
 * the legacy runtime-trigger installer from restoring older, weaker versions
 * of the same triggers by recording the runtime schema version it expects.
 */
export function ensureCompetitiveEconomyHardening(
  env: CompetitiveEconomyHardeningEnv,
): Promise<void> {
  return (installation ??= install(env).catch((error) => {
    installation = null;
    throw error;
  }));
}

async function install(env: CompetitiveEconomyHardeningEnv): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS runtime_schema_state (
       schema_key TEXT PRIMARY KEY,
       version INTEGER NOT NULL,
       updated_at TEXT NOT NULL
     )`,
  ).run();

  // Replace the legacy dynamic-debit guard. A debit ledger row must prove both
  // that the persisted wallet currently equals balance_after and that the
  // wallet actually moved by NEW.amount from the previous ledger balance.
  // This makes a guarded UPDATE that affected zero rows abort the whole D1
  // batch instead of allowing a free match/career spend.
  await env.DB.prepare('DROP TRIGGER IF EXISTS validate_match_entry_ledger_before_insert').run();
  await env.DB.prepare(`CREATE TRIGGER validate_match_entry_ledger_before_insert
    BEFORE INSERT ON coin_ledger
    WHEN NEW.reason IN ('match_entry', 'career_continue')
      AND NEW.amount < 0
      AND (
        NEW.balance_after IS NULL
        OR NEW.balance_after != (
          SELECT online_coins FROM players WHERE id = NEW.player_id
        )
        OR NEW.balance_after != COALESCE(
          (
            SELECT balance_after
            FROM coin_ledger
            WHERE player_id = NEW.player_id
              AND balance_after IS NOT NULL
            ORDER BY created_at DESC, rowid DESC
            LIMIT 1
          ),
          (
            SELECT online_coins - NEW.amount
            FROM players WHERE id = NEW.player_id
          )
        ) + NEW.amount
      )
    BEGIN
      SELECT RAISE(ABORT, 'coin_debit_balance_invariant');
    END`).run();

  // Validate that an authoritative Coin settlement can only pay the funded
  // escrow participants and that its persisted amount matches the escrow pot.
  await env.DB.prepare('DROP TRIGGER IF EXISTS validate_match_coin_settlement_before_insert').run();
  await env.DB.prepare(`CREATE TRIGGER validate_match_coin_settlement_before_insert
    BEFORE INSERT ON match_coin_settlements
    WHEN NOT EXISTS (
      SELECT 1
      FROM match_coin_escrow e
      WHERE e.match_id = NEW.match_id
        AND e.status = 'funded'
        AND e.pot_amount = NEW.amount
        AND (
          (e.player_a_id = NEW.winner_id AND e.player_b_id = NEW.loser_id)
          OR (e.player_b_id = NEW.winner_id AND e.player_a_id = NEW.loser_id)
        )
    )
    BEGIN
      SELECT RAISE(ABORT, 'invalid_match_coin_settlement');
    END`).run();

  // Make the wallet mutation itself idempotent, not only its ledger insert.
  // If an old/recovery path already has a payout ledger key, reprocessing a
  // settlement must not add the pot to the balance a second time.
  await env.DB.prepare('DROP TRIGGER IF EXISTS escrow_prepare_winner_payout').run();
  await env.DB.prepare(`CREATE TRIGGER escrow_prepare_winner_payout
    AFTER INSERT ON match_coin_settlements
    WHEN EXISTS (
      SELECT 1 FROM match_coin_escrow
      WHERE match_id = NEW.match_id AND status = 'funded'
    )
    BEGIN
      INSERT OR IGNORE INTO match_coin_intercepts (
        match_id, winner_id, loser_id, created_at
      ) VALUES (NEW.match_id, NEW.winner_id, NEW.loser_id, NEW.applied_at);

      UPDATE players
      SET online_coins = online_coins + (
        SELECT pot_amount FROM match_coin_escrow WHERE match_id = NEW.match_id
      ),
      updated_at = NEW.applied_at
      WHERE id = NEW.winner_id
        AND NOT EXISTS (
          SELECT 1 FROM coin_ledger
          WHERE idempotency_key = 'match_payout:' || NEW.match_id
        );

      INSERT OR IGNORE INTO coin_ledger (
        id, player_id, amount, balance_after, reason,
        reference_type, reference_id, idempotency_key, metadata_json, created_at
      ) VALUES (
        lower(hex(randomblob(16))),
        NEW.winner_id,
        (SELECT pot_amount FROM match_coin_escrow WHERE match_id = NEW.match_id),
        (SELECT online_coins FROM players WHERE id = NEW.winner_id),
        'match_payout',
        'match',
        NEW.match_id,
        'match_payout:' || NEW.match_id,
        json_object(
          'pot', (SELECT pot_amount FROM match_coin_escrow WHERE match_id = NEW.match_id),
          'entryFee', (SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.match_id)
        ),
        NEW.applied_at
      );

      UPDATE match_coin_escrow
      SET status = 'paid', winner_id = NEW.winner_id, settled_at = NEW.applied_at
      WHERE match_id = NEW.match_id AND status = 'funded';
    END`).run();

  // Refund mutations receive the same balance-level idempotency guarantee.
  await env.DB.prepare('DROP TRIGGER IF EXISTS escrow_refund_draw_or_cancel').run();
  await env.DB.prepare(`CREATE TRIGGER escrow_refund_draw_or_cancel
    AFTER UPDATE OF status ON matches
    WHEN (
        NEW.status = 'cancelled'
        OR (NEW.status IN ('completed', 'abandoned') AND NEW.winner_id IS NULL)
      )
      AND EXISTS (
        SELECT 1 FROM match_coin_escrow
        WHERE match_id = NEW.id AND status = 'funded'
      )
    BEGIN
      UPDATE players
      SET online_coins = online_coins + (
        SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id
      ),
      updated_at = COALESCE(NEW.finished_at, NEW.updated_at)
      WHERE id = NEW.player_a_id
        AND NOT EXISTS (
          SELECT 1 FROM coin_ledger
          WHERE idempotency_key = 'match_refund:' || NEW.id || ':' || NEW.player_a_id
        );

      UPDATE players
      SET online_coins = online_coins + (
        SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id
      ),
      updated_at = COALESCE(NEW.finished_at, NEW.updated_at)
      WHERE id = NEW.player_b_id
        AND NOT EXISTS (
          SELECT 1 FROM coin_ledger
          WHERE idempotency_key = 'match_refund:' || NEW.id || ':' || NEW.player_b_id
        );

      INSERT OR IGNORE INTO coin_ledger (
        id, player_id, amount, balance_after, reason,
        reference_type, reference_id, idempotency_key, metadata_json, created_at
      ) VALUES (
        lower(hex(randomblob(16))),
        NEW.player_a_id,
        (SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id),
        (SELECT online_coins FROM players WHERE id = NEW.player_a_id),
        'match_refund',
        'match',
        NEW.id,
        'match_refund:' || NEW.id || ':' || NEW.player_a_id,
        json_object(
          'entryFee', (SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id),
          'terminalStatus', NEW.status
        ),
        COALESCE(NEW.finished_at, NEW.updated_at)
      );

      INSERT OR IGNORE INTO coin_ledger (
        id, player_id, amount, balance_after, reason,
        reference_type, reference_id, idempotency_key, metadata_json, created_at
      ) VALUES (
        lower(hex(randomblob(16))),
        NEW.player_b_id,
        (SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id),
        (SELECT online_coins FROM players WHERE id = NEW.player_b_id),
        'match_refund',
        'match',
        NEW.id,
        'match_refund:' || NEW.id || ':' || NEW.player_b_id,
        json_object(
          'entryFee', (SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id),
          'terminalStatus', NEW.status
        ),
        COALESCE(NEW.finished_at, NEW.updated_at)
      );

      UPDATE match_coin_escrow
      SET status = 'refunded', winner_id = NULL,
          settled_at = COALESCE(NEW.finished_at, NEW.updated_at)
      WHERE match_id = NEW.id AND status = 'funded';
    END`).run();

  // A player may own at most one active online match, across every variant and
  // every entry path. This closes races between classic9/classic16 queues,
  // challenges and rematch funding running in different Durable Objects.
  await env.DB.prepare('DROP TRIGGER IF EXISTS enforce_single_active_match_before_insert').run();
  await env.DB.prepare(`CREATE TRIGGER enforce_single_active_match_before_insert
    BEFORE INSERT ON matches
    WHEN NEW.status IN (${ACTIVE_STATUSES})
      AND EXISTS (
        SELECT 1 FROM matches m
        WHERE m.status IN (${ACTIVE_STATUSES})
          AND (
            m.player_a_id = NEW.player_a_id
            OR m.player_b_id = NEW.player_a_id
            OR m.player_a_id = NEW.player_b_id
            OR m.player_b_id = NEW.player_b_id
          )
      )
    BEGIN
      SELECT RAISE(ABORT, 'active_match_conflict');
    END`).run();

  await env.DB.prepare('DROP TRIGGER IF EXISTS enforce_single_active_match_before_reactivate').run();
  await env.DB.prepare(`CREATE TRIGGER enforce_single_active_match_before_reactivate
    BEFORE UPDATE OF status ON matches
    WHEN NEW.status IN (${ACTIVE_STATUSES})
      AND OLD.status NOT IN (${ACTIVE_STATUSES})
      AND EXISTS (
        SELECT 1 FROM matches m
        WHERE m.id != NEW.id
          AND m.status IN (${ACTIVE_STATUSES})
          AND (
            m.player_a_id = NEW.player_a_id
            OR m.player_b_id = NEW.player_a_id
            OR m.player_a_id = NEW.player_b_id
            OR m.player_b_id = NEW.player_b_id
          )
      )
    BEGIN
      SELECT RAISE(ABORT, 'active_match_conflict');
    END`).run();

  // Defense in depth for hidden-MMR boosting. The queue already skips pairs
  // at the limit and economy.ts checks them before funding; this trigger closes
  // cross-DO races by rejecting the fourth started/settled ranked match within
  // a rolling 24-hour window at the database boundary.
  await env.DB.prepare('DROP TRIGGER IF EXISTS enforce_ranked_pair_limit_before_insert').run();
  await env.DB.prepare(`CREATE TRIGGER enforce_ranked_pair_limit_before_insert
    BEFORE INSERT ON matches
    WHEN NEW.mode = 'ranked'
      AND (
        SELECT COUNT(*)
        FROM matches recent
        WHERE recent.mode = 'ranked'
          AND recent.started_at IS NOT NULL
          AND recent.status IN (${TERMINAL_RATED_STATUSES})
          AND julianday(COALESCE(recent.finished_at, recent.updated_at, recent.created_at))
                >= julianday(NEW.created_at) - 1
          AND (
            (recent.player_a_id = NEW.player_a_id AND recent.player_b_id = NEW.player_b_id)
            OR (recent.player_a_id = NEW.player_b_id AND recent.player_b_id = NEW.player_a_id)
          )
      ) >= ${MAX_RATED_PAIR_MATCHES_24H}
    BEGIN
      SELECT RAISE(ABORT, 'ranked_pair_limit');
    END`).run();

  // Clean any historical duplicate active rooms before the invariant becomes
  // authoritative. Cancelling a funded duplicate uses the hardened refund
  // trigger above, so Coins return exactly once.
  const now = new Date().toISOString();
  await env.DB.prepare(`UPDATE matches
    SET status = 'cancelled',
        winner_id = NULL,
        finish_reason = COALESCE(finish_reason, 'duplicate_active_match'),
        finished_at = COALESCE(finished_at, ?),
        updated_at = ?
    WHERE status IN (${ACTIVE_STATUSES})
      AND EXISTS (
        SELECT 1 FROM matches newer
        WHERE newer.id != matches.id
          AND newer.status IN (${ACTIVE_STATUSES})
          AND (
            newer.player_a_id = matches.player_a_id
            OR newer.player_b_id = matches.player_a_id
            OR newer.player_a_id = matches.player_b_id
            OR newer.player_b_id = matches.player_b_id
          )
          AND (
            newer.created_at > matches.created_at
            OR (newer.created_at = matches.created_at AND newer.id > matches.id)
          )
      )`)
    .bind(now, now)
    .run();

  // entry.ts currently expects runtime trigger schema version 2. Recording that
  // version prevents its legacy installer from replacing these hardened forms.
  await env.DB.prepare(
    `INSERT INTO runtime_schema_state (schema_key, version, updated_at)
     VALUES ('runtime_triggers', 2, ?)
     ON CONFLICT(schema_key) DO UPDATE SET
       version = excluded.version,
       updated_at = excluded.updated_at`,
  )
    .bind(now)
    .run();
}
