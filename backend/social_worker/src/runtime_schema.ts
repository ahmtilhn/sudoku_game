export interface RuntimeSchemaEnv {
  DB: D1Database;
}

const RUNTIME_TRIGGER_SCHEMA_KEY = 'runtime_triggers';
const RUNTIME_TRIGGER_SCHEMA_VERSION = 1;

let installation: Promise<void> | null = null;

export async function ensureRuntimeSchema(
  env: RuntimeSchemaEnv,
): Promise<void> {
  installation ??= installRuntimeSchema(env).catch((error: unknown) => {
    installation = null;
    throw error;
  });
  await installation;
}

async function installRuntimeSchema(env: RuntimeSchemaEnv): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS runtime_schema_state (
       schema_key TEXT PRIMARY KEY,
       version INTEGER NOT NULL,
       updated_at TEXT NOT NULL
     )`,
  ).run();

  const current = await env.DB.prepare(
    'SELECT version FROM runtime_schema_state WHERE schema_key = ? LIMIT 1',
  )
    .bind(RUNTIME_TRIGGER_SCHEMA_KEY)
    .first<{ version: number }>();
  if (current?.version === RUNTIME_TRIGGER_SCHEMA_VERSION) return;

  for (const name of RUNTIME_TRIGGER_NAMES) {
    await env.DB.prepare(`DROP TRIGGER IF EXISTS ${name}`).run();
  }
  for (const statement of RUNTIME_TRIGGER_STATEMENTS) {
    await env.DB.prepare(statement).run();
  }

  await env.DB.prepare(
    `INSERT INTO runtime_schema_state (schema_key, version, updated_at)
     VALUES (?, ?, ?)
     ON CONFLICT(schema_key) DO UPDATE SET
       version = excluded.version,
       updated_at = excluded.updated_at`,
  )
    .bind(
      RUNTIME_TRIGGER_SCHEMA_KEY,
      RUNTIME_TRIGGER_SCHEMA_VERSION,
      new Date().toISOString(),
    )
    .run();
}

const RUNTIME_TRIGGER_NAMES = [
  'players_confirm_custom_name_after_insert',
  'players_confirm_custom_name_after_update',
  'cap_daily_career_reward_preparations',
  'prevent_negative_player_coin_balance',
  'validate_match_entry_ledger_before_insert',
  'auto_grant_coin_achievement_rewards',
  'prevent_deleted_account_recreation',
  'escrow_prepare_winner_payout',
  'escrow_refund_draw_or_cancel',
  'fund_direct_challenge_match',
] as const;

const RUNTIME_TRIGGER_STATEMENTS: readonly string[] = [
  `CREATE TRIGGER IF NOT EXISTS players_confirm_custom_name_after_insert
   AFTER INSERT ON players
   WHEN NEW.display_name != 'Sudoku Player'
   BEGIN
     UPDATE players
     SET profile_confirmed = 1, name_source = 'custom'
     WHERE id = NEW.id;
   END`,
  `CREATE TRIGGER IF NOT EXISTS players_confirm_custom_name_after_update
   AFTER UPDATE OF display_name ON players
   WHEN NEW.display_name != OLD.display_name
     AND NEW.display_name != 'Sudoku Player'
   BEGIN
     UPDATE players
     SET profile_confirmed = 1, name_source = 'custom'
     WHERE id = NEW.id;
   END`,
  `CREATE TRIGGER IF NOT EXISTS cap_daily_career_reward_preparations
   BEFORE INSERT ON reward_claims
   WHEN NEW.reward_type = 'career_rewarded_ad'
     AND (
       SELECT COUNT(*) FROM reward_claims
       WHERE player_id = NEW.player_id
         AND reward_type = 'career_rewarded_ad'
         AND substr(prepared_at, 1, 10) = substr(NEW.prepared_at, 1, 10)
         AND status IN ('prepared', 'claimed')
     ) >= 20
   BEGIN
     SELECT RAISE(ABORT, 'career_reward_daily_cap');
   END`,
  `CREATE TRIGGER IF NOT EXISTS prevent_negative_player_coin_balance
   BEFORE UPDATE OF online_coins ON players
   WHEN NEW.online_coins < 0
   BEGIN
     SELECT RAISE(ABORT, 'negative_coin_balance');
   END`,
  `CREATE TRIGGER IF NOT EXISTS validate_match_entry_ledger_before_insert
   BEFORE INSERT ON coin_ledger
   WHEN NEW.reason = 'match_entry'
     AND NEW.amount = -100
     AND NEW.balance_after != (
       COALESCE(
         (
           SELECT balance_after
           FROM coin_ledger
           WHERE player_id = NEW.player_id
             AND balance_after IS NOT NULL
           ORDER BY created_at DESC, rowid DESC
           LIMIT 1
         ),
         (SELECT online_coins + 100 FROM players WHERE id = NEW.player_id)
       ) - 100
     )
   BEGIN
     SELECT RAISE(ABORT, 'match_entry_balance_invariant');
   END`,
  `CREATE TRIGGER IF NOT EXISTS auto_grant_coin_achievement_rewards
   AFTER UPDATE OF games_played, wins, rating ON players
   BEGIN
     UPDATE players
     SET online_coins = online_coins + 50
     WHERE id = NEW.id
       AND NEW.wins >= 1
       AND NOT EXISTS (
         SELECT 1 FROM coin_ledger
         WHERE idempotency_key = 'achievement:' || NEW.id || ':first_win'
       );
     INSERT OR IGNORE INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 50,
            (SELECT online_coins FROM players WHERE id = NEW.id),
            'achievement_reward', 'achievement', 'first_win',
            'achievement:' || NEW.id || ':first_win',
            json_object('tier', 'bronze'), NEW.updated_at
     WHERE NEW.wins >= 1;
     INSERT OR IGNORE INTO reward_claims (
       id, player_id, reward_type, reward_key, amount,
       status, prepared_at, claimed_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 'achievement_reward',
            'first_win', 50, 'claimed', NEW.updated_at, NEW.updated_at
     WHERE NEW.wins >= 1;

     UPDATE players
     SET online_coins = online_coins + 100
     WHERE id = NEW.id
       AND NEW.wins >= 10
       AND NOT EXISTS (
         SELECT 1 FROM coin_ledger
         WHERE idempotency_key = 'achievement:' || NEW.id || ':wins_10'
       );
     INSERT OR IGNORE INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 100,
            (SELECT online_coins FROM players WHERE id = NEW.id),
            'achievement_reward', 'achievement', 'wins_10',
            'achievement:' || NEW.id || ':wins_10',
            json_object('tier', 'silver'), NEW.updated_at
     WHERE NEW.wins >= 10;
     INSERT OR IGNORE INTO reward_claims (
       id, player_id, reward_type, reward_key, amount,
       status, prepared_at, claimed_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 'achievement_reward',
            'wins_10', 100, 'claimed', NEW.updated_at, NEW.updated_at
     WHERE NEW.wins >= 10;

     UPDATE players
     SET online_coins = online_coins + 100
     WHERE id = NEW.id
       AND NEW.games_played >= 25
       AND NOT EXISTS (
         SELECT 1 FROM coin_ledger
         WHERE idempotency_key = 'achievement:' || NEW.id || ':games_25'
       );
     INSERT OR IGNORE INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 100,
            (SELECT online_coins FROM players WHERE id = NEW.id),
            'achievement_reward', 'achievement', 'games_25',
            'achievement:' || NEW.id || ':games_25',
            json_object('tier', 'silver'), NEW.updated_at
     WHERE NEW.games_played >= 25;
     INSERT OR IGNORE INTO reward_claims (
       id, player_id, reward_type, reward_key, amount,
       status, prepared_at, claimed_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 'achievement_reward',
            'games_25', 100, 'claimed', NEW.updated_at, NEW.updated_at
     WHERE NEW.games_played >= 25;

     UPDATE players
     SET online_coins = online_coins + 250
     WHERE id = NEW.id
       AND NEW.wins >= 50
       AND NOT EXISTS (
         SELECT 1 FROM coin_ledger
         WHERE idempotency_key = 'achievement:' || NEW.id || ':wins_50'
       );
     INSERT OR IGNORE INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 250,
            (SELECT online_coins FROM players WHERE id = NEW.id),
            'achievement_reward', 'achievement', 'wins_50',
            'achievement:' || NEW.id || ':wins_50',
            json_object('tier', 'gold'), NEW.updated_at
     WHERE NEW.wins >= 50;
     INSERT OR IGNORE INTO reward_claims (
       id, player_id, reward_type, reward_key, amount,
       status, prepared_at, claimed_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 'achievement_reward',
            'wins_50', 250, 'claimed', NEW.updated_at, NEW.updated_at
     WHERE NEW.wins >= 50;

     UPDATE players
     SET online_coins = online_coins + 250
     WHERE id = NEW.id
       AND NEW.rating >= 1200
       AND NOT EXISTS (
         SELECT 1 FROM coin_ledger
         WHERE idempotency_key = 'achievement:' || NEW.id || ':rating_1200'
       );
     INSERT OR IGNORE INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 250,
            (SELECT online_coins FROM players WHERE id = NEW.id),
            'achievement_reward', 'achievement', 'rating_1200',
            'achievement:' || NEW.id || ':rating_1200',
            json_object('tier', 'gold'), NEW.updated_at
     WHERE NEW.rating >= 1200;
     INSERT OR IGNORE INTO reward_claims (
       id, player_id, reward_type, reward_key, amount,
       status, prepared_at, claimed_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 'achievement_reward',
            'rating_1200', 250, 'claimed', NEW.updated_at, NEW.updated_at
     WHERE NEW.rating >= 1200;

     UPDATE players
     SET online_coins = online_coins + 500
     WHERE id = NEW.id
       AND NEW.rating >= 1500
       AND NOT EXISTS (
         SELECT 1 FROM coin_ledger
         WHERE idempotency_key = 'achievement:' || NEW.id || ':rating_1500'
       );
     INSERT OR IGNORE INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 500,
            (SELECT online_coins FROM players WHERE id = NEW.id),
            'achievement_reward', 'achievement', 'rating_1500',
            'achievement:' || NEW.id || ':rating_1500',
            json_object('tier', 'platinum'), NEW.updated_at
     WHERE NEW.rating >= 1500;
     INSERT OR IGNORE INTO reward_claims (
       id, player_id, reward_type, reward_key, amount,
       status, prepared_at, claimed_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 'achievement_reward',
            'rating_1500', 500, 'claimed', NEW.updated_at, NEW.updated_at
     WHERE NEW.rating >= 1500;

     UPDATE players
     SET online_coins = online_coins + 1000
     WHERE id = NEW.id
       AND NEW.wins >= 250
       AND NOT EXISTS (
         SELECT 1 FROM coin_ledger
         WHERE idempotency_key = 'achievement:' || NEW.id || ':wins_250'
       );
     INSERT OR IGNORE INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 1000,
            (SELECT online_coins FROM players WHERE id = NEW.id),
            'achievement_reward', 'achievement', 'wins_250',
            'achievement:' || NEW.id || ':wins_250',
            json_object('tier', 'milestone'), NEW.updated_at
     WHERE NEW.wins >= 250;
     INSERT OR IGNORE INTO reward_claims (
       id, player_id, reward_type, reward_key, amount,
       status, prepared_at, claimed_at
     )
     SELECT lower(hex(randomblob(16))), NEW.id, 'achievement_reward',
            'wins_250', 1000, 'claimed', NEW.updated_at, NEW.updated_at
     WHERE NEW.wins >= 250;
   END`,
  `CREATE TRIGGER IF NOT EXISTS prevent_deleted_account_recreation
   BEFORE INSERT ON players
   WHEN EXISTS (
     SELECT 1 FROM deleted_accounts d WHERE d.firebase_uid = NEW.firebase_uid
   )
   BEGIN
     SELECT RAISE(ABORT, 'account_deleted');
   END`,
  `CREATE TRIGGER IF NOT EXISTS escrow_prepare_winner_payout
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
     )
     WHERE id = NEW.winner_id;
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
   END`,
  `CREATE TRIGGER IF NOT EXISTS escrow_refund_draw_or_cancel
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
     )
     WHERE id = NEW.player_a_id;
     UPDATE players
     SET online_coins = online_coins + (
       SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id
     )
     WHERE id = NEW.player_b_id;
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
   END`,
  `CREATE TRIGGER IF NOT EXISTS fund_direct_challenge_match
   AFTER INSERT ON matches
   WHEN NEW.challenge_id IS NOT NULL
   BEGIN
     INSERT INTO match_coin_escrow (
       match_id, player_a_id, player_b_id, player_a_amount,
       player_b_amount, pot_amount, status, funded_at
     )
     SELECT NEW.id, NEW.player_a_id, NEW.player_b_id,
            CASE NEW.difficulty
              WHEN 'beginner' THEN 100
              WHEN 'easy' THEN 150
              WHEN 'medium' THEN 250
              WHEN 'hard' THEN 400
              WHEN 'expert' THEN 650
            END,
            CASE NEW.difficulty
              WHEN 'beginner' THEN 100
              WHEN 'easy' THEN 150
              WHEN 'medium' THEN 250
              WHEN 'hard' THEN 400
              WHEN 'expert' THEN 650
            END,
            CASE NEW.difficulty
              WHEN 'beginner' THEN 200
              WHEN 'easy' THEN 300
              WHEN 'medium' THEN 500
              WHEN 'hard' THEN 800
              WHEN 'expert' THEN 1300
            END,
            'funded',
            NEW.created_at
     WHERE (SELECT online_coins FROM players WHERE id = NEW.player_a_id) >=
           CASE NEW.difficulty
             WHEN 'beginner' THEN 100
             WHEN 'easy' THEN 150
             WHEN 'medium' THEN 250
             WHEN 'hard' THEN 400
             WHEN 'expert' THEN 650
           END
       AND (SELECT online_coins FROM players WHERE id = NEW.player_b_id) >=
           CASE NEW.difficulty
             WHEN 'beginner' THEN 100
             WHEN 'easy' THEN 150
             WHEN 'medium' THEN 250
             WHEN 'hard' THEN 400
             WHEN 'expert' THEN 650
           END;
     UPDATE challenges
     SET status = 'cancelled', room_id = NULL, updated_at = NEW.created_at
     WHERE id = NEW.challenge_id
       AND NOT EXISTS (
         SELECT 1 FROM match_coin_escrow WHERE match_id = NEW.id
       );
     UPDATE matches
     SET status = 'cancelled', winner_id = NULL,
         finish_reason = 'insufficient_coins',
         finished_at = NEW.created_at, updated_at = NEW.created_at
     WHERE id = NEW.id
       AND NOT EXISTS (
         SELECT 1 FROM match_coin_escrow WHERE match_id = NEW.id
       );
     UPDATE players
     SET online_coins = online_coins - (
       SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id
     ), updated_at = NEW.created_at
     WHERE id = NEW.player_a_id
       AND EXISTS (
         SELECT 1 FROM match_coin_escrow
         WHERE match_id = NEW.id AND status = 'funded'
       );
     INSERT INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))),
            NEW.player_a_id,
            -player_a_amount,
            (SELECT online_coins FROM players WHERE id = NEW.player_a_id),
            'match_entry',
            'match',
            NEW.id,
            'match_entry:' || NEW.id || ':' || NEW.player_a_id,
            json_object('entryFee', player_a_amount, 'pot', pot_amount, 'source', 'direct_challenge'),
            NEW.created_at
     FROM match_coin_escrow
     WHERE match_id = NEW.id AND status = 'funded';
     UPDATE players
     SET online_coins = online_coins - (
       SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id
     ), updated_at = NEW.created_at
     WHERE id = NEW.player_b_id
       AND EXISTS (
         SELECT 1 FROM match_coin_escrow
         WHERE match_id = NEW.id AND status = 'funded'
       );
     INSERT INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     )
     SELECT lower(hex(randomblob(16))),
            NEW.player_b_id,
            -player_b_amount,
            (SELECT online_coins FROM players WHERE id = NEW.player_b_id),
            'match_entry',
            'match',
            NEW.id,
            'match_entry:' || NEW.id || ':' || NEW.player_b_id,
            json_object('entryFee', player_b_amount, 'pot', pot_amount, 'source', 'direct_challenge'),
            NEW.created_at
     FROM match_coin_escrow
     WHERE match_id = NEW.id AND status = 'funded';
   END`,
];
