export interface CompetitiveRecoveryHardeningEnv {
  DB: D1Database;
}

let installation: Promise<void> | null = null;

const ACTIVE_STATUSES = "'waiting', 'ready_window', 'countdown', 'active', 'paused'";
const TERMINAL_RATED_STATUSES = "'completed', 'forfeited', 'abandoned'";
const MAX_RATED_PAIR_MATCHES_24H = 3;

/**
 * Recovery-specific refinements installed after the main competitive hardening.
 * Security checks still reject genuinely new conflicting work, while exact
 * replays of an already-persisted match/settlement are allowed to reach their
 * ON CONFLICT idempotency boundary.
 */
export function ensureCompetitiveRecoveryHardening(
  env: CompetitiveRecoveryHardeningEnv,
): Promise<void> {
  return (installation ??= install(env).catch((error) => {
    installation = null;
    throw error;
  }));
}

async function install(env: CompetitiveRecoveryHardeningEnv): Promise<void> {
  await env.DB.prepare(
    'DROP TRIGGER IF EXISTS validate_match_coin_settlement_before_insert',
  ).run();
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
      AND NOT EXISTS (
        SELECT 1
        FROM match_coin_settlements s
        WHERE s.match_id = NEW.match_id
          AND s.winner_id = NEW.winner_id
          AND s.loser_id = NEW.loser_id
          AND s.amount = NEW.amount
      )
    BEGIN
      SELECT RAISE(ABORT, 'invalid_match_coin_settlement');
    END`).run();

  await env.DB.prepare(
    'DROP TRIGGER IF EXISTS enforce_single_active_match_before_insert',
  ).run();
  await env.DB.prepare(`CREATE TRIGGER enforce_single_active_match_before_insert
    BEFORE INSERT ON matches
    WHEN NEW.status IN (${ACTIVE_STATUSES})
      AND NOT EXISTS (
        SELECT 1 FROM matches replay
        WHERE replay.id = NEW.id OR replay.room_id = NEW.room_id
      )
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

  await env.DB.prepare(
    'DROP TRIGGER IF EXISTS enforce_ranked_pair_limit_before_insert',
  ).run();
  await env.DB.prepare(`CREATE TRIGGER enforce_ranked_pair_limit_before_insert
    BEFORE INSERT ON matches
    WHEN NEW.mode = 'ranked'
      AND NOT EXISTS (
        SELECT 1 FROM matches replay
        WHERE replay.id = NEW.id OR replay.room_id = NEW.room_id
      )
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
}
