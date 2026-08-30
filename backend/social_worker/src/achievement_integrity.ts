export interface AchievementIntegrityEnv {
  DB: D1Database;
}

const SCHEMA_KEY = 'achievement_integrity';
const SCHEMA_VERSION = 1;

let installation: Promise<void> | null = null;

export function ensureAchievementIntegrity(
  env: AchievementIntegrityEnv,
): Promise<void> {
  return (installation ??= install(env).catch((error) => {
    installation = null;
    throw error;
  }));
}

async function install(env: AchievementIntegrityEnv): Promise<void> {
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
    .bind(SCHEMA_KEY)
    .first<{ version: number }>();
  if (current?.version === SCHEMA_VERSION) return;

  for (const trigger of [
    'auto_grant_coin_achievement_rewards',
    'achievement_unlock_from_variant_progress',
    'achievement_reward_after_automatic_unlock',
    'achievement_count_after_unlock',
    'friend_link_after_accept',
    'friend_link_after_insert_accepted',
  ]) {
    await env.DB.prepare(`DROP TRIGGER IF EXISTS ${trigger}`).run();
  }

  await env.DB.prepare(
    `UPDATE achievement_definitions
     SET platform_mirror_key = NULL, platform_mirror_enabled = 0
     WHERE platform_mirror_enabled != 0 OR platform_mirror_key IS NOT NULL`,
  ).run();
  await env.DB.prepare('DELETE FROM platform_achievement_mirror_queue').run();
  await env.DB.prepare(
    `UPDATE player_achievements
     SET platform_mirror_status = 'not_applicable'
     WHERE platform_mirror_status != 'not_applicable'`,
  ).run();

  await env.DB.prepare(
    `CREATE TRIGGER achievement_reward_after_automatic_unlock
     AFTER INSERT ON player_achievements
     WHEN NEW.source = 'automatic'
       AND COALESCE((
         SELECT reward_amount FROM achievement_definitions WHERE id = NEW.achievement_id
       ), 0) > 0
     BEGIN
       UPDATE players
       SET online_coins = online_coins + COALESCE((
             SELECT reward_amount FROM achievement_definitions WHERE id = NEW.achievement_id
           ), 0),
           updated_at = NEW.updated_at
       WHERE id = NEW.player_id
         AND NOT EXISTS (
           SELECT 1 FROM coin_ledger
           WHERE idempotency_key = 'achievement:' || NEW.player_id || ':' || NEW.achievement_id
         );

       INSERT OR IGNORE INTO coin_ledger (
         id, player_id, amount, balance_after, reason,
         reference_type, reference_id, idempotency_key, metadata_json, created_at
       )
       SELECT lower(hex(randomblob(16))), NEW.player_id, d.reward_amount,
              (SELECT online_coins FROM players WHERE id = NEW.player_id),
              'achievement_reward', 'achievement', NEW.achievement_id,
              'achievement:' || NEW.player_id || ':' || NEW.achievement_id,
              json_object('tier', d.tier, 'source', 'automatic'), NEW.updated_at
       FROM achievement_definitions d
       WHERE d.id = NEW.achievement_id AND d.reward_amount > 0;

       INSERT OR IGNORE INTO reward_claims (
         id, player_id, reward_type, reward_key, amount,
         status, prepared_at, claimed_at
       )
       SELECT lower(hex(randomblob(16))), NEW.player_id,
              'achievement_reward', NEW.achievement_id, d.reward_amount,
              'claimed', NEW.updated_at, NEW.updated_at
       FROM achievement_definitions d
       WHERE d.id = NEW.achievement_id AND d.reward_amount > 0;
     END`,
  ).run();

  await env.DB.prepare(
    `CREATE TRIGGER achievement_count_after_unlock
     AFTER INSERT ON player_achievements
     BEGIN
       UPDATE players
       SET achievement_count = (
             SELECT COUNT(*) FROM player_achievements WHERE player_id = NEW.player_id
           ),
           updated_at = NEW.updated_at
       WHERE id = NEW.player_id;
     END`,
  ).run();

  await env.DB.prepare(
    `CREATE TRIGGER achievement_unlock_from_variant_progress
     AFTER UPDATE OF rating, games_played, wins ON player_variant_ratings
     WHEN NEW.scope = 'global'
     BEGIN
       INSERT OR IGNORE INTO player_achievements (
         player_id, achievement_id, unlocked_at, progress, source,
         platform_mirror_status, updated_at
       )
       SELECT NEW.player_id, d.id, NEW.updated_at, 100, 'automatic',
              'not_applicable', NEW.updated_at
       FROM achievement_definitions d
       WHERE d.id IN (
           'first_win', 'wins_10', 'games_25', 'wins_50',
           'rating_1200', 'rating_1500', 'wins_250'
         )
         AND (
           (d.id = 'first_win' AND (
             SELECT COALESCE(SUM(v.wins), 0)
             FROM player_variant_ratings v
             WHERE v.player_id = NEW.player_id AND v.scope = 'global'
           ) >= 1)
           OR (d.id = 'wins_10' AND (
             SELECT COALESCE(SUM(v.wins), 0)
             FROM player_variant_ratings v
             WHERE v.player_id = NEW.player_id AND v.scope = 'global'
           ) >= 10)
           OR (d.id = 'games_25' AND (
             SELECT COALESCE(SUM(v.games_played), 0)
             FROM player_variant_ratings v
             WHERE v.player_id = NEW.player_id AND v.scope = 'global'
           ) >= 25)
           OR (d.id = 'wins_50' AND (
             SELECT COALESCE(SUM(v.wins), 0)
             FROM player_variant_ratings v
             WHERE v.player_id = NEW.player_id AND v.scope = 'global'
           ) >= 50)
           OR (d.id = 'rating_1200' AND (
             SELECT COALESCE(MAX(v.rating), 0)
             FROM player_variant_ratings v
             WHERE v.player_id = NEW.player_id AND v.scope = 'global'
           ) >= 1200)
           OR (d.id = 'rating_1500' AND (
             SELECT COALESCE(MAX(v.rating), 0)
             FROM player_variant_ratings v
             WHERE v.player_id = NEW.player_id AND v.scope = 'global'
           ) >= 1500)
           OR (d.id = 'wins_250' AND (
             SELECT COALESCE(SUM(v.wins), 0)
             FROM player_variant_ratings v
             WHERE v.player_id = NEW.player_id AND v.scope = 'global'
           ) >= 250)
         );
     END`,
  ).run();

  await env.DB.prepare(
    `CREATE TRIGGER friend_link_after_accept
     AFTER UPDATE OF status ON friendships
     WHEN NEW.status = 'accepted' AND OLD.status != 'accepted'
     BEGIN
       INSERT OR IGNORE INTO player_achievements (
         player_id, achievement_id, unlocked_at, progress, source,
         platform_mirror_status, updated_at
       )
       SELECT NEW.player_low_id, 'friend_link', NEW.updated_at, 100,
              'automatic', 'not_applicable', NEW.updated_at
       WHERE EXISTS (SELECT 1 FROM achievement_definitions WHERE id = 'friend_link');
       INSERT OR IGNORE INTO player_achievements (
         player_id, achievement_id, unlocked_at, progress, source,
         platform_mirror_status, updated_at
       )
       SELECT NEW.player_high_id, 'friend_link', NEW.updated_at, 100,
              'automatic', 'not_applicable', NEW.updated_at
       WHERE EXISTS (SELECT 1 FROM achievement_definitions WHERE id = 'friend_link');
     END`,
  ).run();

  await env.DB.prepare(
    `CREATE TRIGGER friend_link_after_insert_accepted
     AFTER INSERT ON friendships
     WHEN NEW.status = 'accepted'
     BEGIN
       INSERT OR IGNORE INTO player_achievements (
         player_id, achievement_id, unlocked_at, progress, source,
         platform_mirror_status, updated_at
       )
       SELECT NEW.player_low_id, 'friend_link', NEW.updated_at, 100,
              'automatic', 'not_applicable', NEW.updated_at
       WHERE EXISTS (SELECT 1 FROM achievement_definitions WHERE id = 'friend_link');
       INSERT OR IGNORE INTO player_achievements (
         player_id, achievement_id, unlocked_at, progress, source,
         platform_mirror_status, updated_at
       )
       SELECT NEW.player_high_id, 'friend_link', NEW.updated_at, 100,
              'automatic', 'not_applicable', NEW.updated_at
       WHERE EXISTS (SELECT 1 FROM achievement_definitions WHERE id = 'friend_link');
     END`,
  ).run();

  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO runtime_schema_state (schema_key, version, updated_at)
     VALUES (?, ?, ?)
     ON CONFLICT(schema_key) DO UPDATE SET
       version = excluded.version,
       updated_at = excluded.updated_at`,
  )
    .bind(SCHEMA_KEY, SCHEMA_VERSION, now)
    .run();
}
