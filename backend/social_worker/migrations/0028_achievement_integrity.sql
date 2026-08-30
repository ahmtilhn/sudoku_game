PRAGMA foreign_keys = ON;

-- The legacy trigger only watched players.games_played/wins/rating, which are
-- classic9 compatibility fields. All active ranked achievements are now driven
-- by player_variant_ratings so classic9 and classic16 contribute equally.
DROP TRIGGER IF EXISTS auto_grant_coin_achievement_rewards;
DROP TRIGGER IF EXISTS achievement_unlock_from_variant_progress;
DROP TRIGGER IF EXISTS achievement_reward_after_automatic_unlock;
DROP TRIGGER IF EXISTS achievement_count_after_unlock;
DROP TRIGGER IF EXISTS friend_link_after_accept;
DROP TRIGGER IF EXISTS friend_link_after_insert_accepted;

-- Platform mirroring is intentionally disabled in D1. The app mirrors only the
-- Play Games achievements for which a real exported platform ID exists. This
-- removes stale queue entries for achievements that had no corresponding Play
-- Console resource and makes D1 the single source of truth for unlock state.
UPDATE achievement_definitions
SET platform_mirror_key = NULL,
    platform_mirror_enabled = 0
WHERE platform_mirror_enabled != 0 OR platform_mirror_key IS NOT NULL;

DELETE FROM platform_achievement_mirror_queue;
UPDATE player_achievements
SET platform_mirror_status = 'not_applicable',
    updated_at = COALESCE(updated_at, unlocked_at)
WHERE platform_mirror_status != 'not_applicable';

-- Future-only definitions must not appear as broken achievements before their
-- product features exist. Keep an already-earned historical row intact.
DELETE FROM achievement_definitions
WHERE id IN ('country_contributor', 'tournament_podium')
  AND NOT EXISTS (
    SELECT 1 FROM player_achievements pa
    WHERE pa.achievement_id = achievement_definitions.id
  );

-- Any automatic unlock with a positive configured reward receives its Coin in
-- the same SQLite statement transaction. The ledger key makes both the wallet
-- mutation and the ledger row exactly-once.
CREATE TRIGGER achievement_reward_after_automatic_unlock
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
  SELECT lower(hex(randomblob(16))),
         NEW.player_id,
         d.reward_amount,
         (SELECT online_coins FROM players WHERE id = NEW.player_id),
         'achievement_reward',
         'achievement',
         NEW.achievement_id,
         'achievement:' || NEW.player_id || ':' || NEW.achievement_id,
         json_object('tier', d.tier, 'source', 'automatic'),
         NEW.updated_at
  FROM achievement_definitions d
  WHERE d.id = NEW.achievement_id
    AND d.reward_amount > 0;

  INSERT OR IGNORE INTO reward_claims (
    id, player_id, reward_type, reward_key, amount,
    status, prepared_at, claimed_at
  )
  SELECT lower(hex(randomblob(16))),
         NEW.player_id,
         'achievement_reward',
         NEW.achievement_id,
         d.reward_amount,
         'claimed',
         NEW.updated_at,
         NEW.updated_at
  FROM achievement_definitions d
  WHERE d.id = NEW.achievement_id
    AND d.reward_amount > 0;
END;

CREATE TRIGGER achievement_count_after_unlock
AFTER INSERT ON player_achievements
BEGIN
  UPDATE players
  SET achievement_count = (
        SELECT COUNT(*) FROM player_achievements WHERE player_id = NEW.player_id
      ),
      updated_at = NEW.updated_at
  WHERE id = NEW.player_id;
END;

CREATE TRIGGER achievement_unlock_from_variant_progress
AFTER UPDATE OF rating, games_played, wins ON player_variant_ratings
WHEN NEW.scope = 'global'
BEGIN
  INSERT OR IGNORE INTO player_achievements (
    player_id, achievement_id, unlocked_at, progress, source,
    platform_mirror_status, updated_at
  )
  SELECT NEW.player_id,
         d.id,
         NEW.updated_at,
         100,
         'automatic',
         'not_applicable',
         NEW.updated_at
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
END;

-- Friendly Rival is earned by both sides of a newly accepted friendship.
CREATE TRIGGER friend_link_after_accept
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
END;

CREATE TRIGGER friend_link_after_insert_accepted
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
END;

-- Backfill ranked achievements from the authoritative per-variant counters.
-- AFTER INSERT triggers above also backfill missing Coin rewards exactly once.
INSERT OR IGNORE INTO player_achievements (
  player_id, achievement_id, unlocked_at, progress, source,
  platform_mirror_status, updated_at
)
SELECT p.id,
       d.id,
       p.updated_at,
       100,
       'automatic',
       'not_applicable',
       p.updated_at
FROM players p
JOIN achievement_definitions d
  ON d.id IN (
    'first_win', 'wins_10', 'games_25', 'wins_50',
    'rating_1200', 'rating_1500', 'wins_250'
  )
WHERE
  (d.id = 'first_win' AND (
    SELECT COALESCE(SUM(v.wins), 0)
    FROM player_variant_ratings v
    WHERE v.player_id = p.id AND v.scope = 'global'
  ) >= 1)
  OR (d.id = 'wins_10' AND (
    SELECT COALESCE(SUM(v.wins), 0)
    FROM player_variant_ratings v
    WHERE v.player_id = p.id AND v.scope = 'global'
  ) >= 10)
  OR (d.id = 'games_25' AND (
    SELECT COALESCE(SUM(v.games_played), 0)
    FROM player_variant_ratings v
    WHERE v.player_id = p.id AND v.scope = 'global'
  ) >= 25)
  OR (d.id = 'wins_50' AND (
    SELECT COALESCE(SUM(v.wins), 0)
    FROM player_variant_ratings v
    WHERE v.player_id = p.id AND v.scope = 'global'
  ) >= 50)
  OR (d.id = 'rating_1200' AND (
    SELECT COALESCE(MAX(v.rating), 0)
    FROM player_variant_ratings v
    WHERE v.player_id = p.id AND v.scope = 'global'
  ) >= 1200)
  OR (d.id = 'rating_1500' AND (
    SELECT COALESCE(MAX(v.rating), 0)
    FROM player_variant_ratings v
    WHERE v.player_id = p.id AND v.scope = 'global'
  ) >= 1500)
  OR (d.id = 'wins_250' AND (
    SELECT COALESCE(SUM(v.wins), 0)
    FROM player_variant_ratings v
    WHERE v.player_id = p.id AND v.scope = 'global'
  ) >= 250);

-- Backfill social and streak achievements that may have been earned before the
-- automatic triggers existed.
INSERT OR IGNORE INTO player_achievements (
  player_id, achievement_id, unlocked_at, progress, source,
  platform_mirror_status, updated_at
)
SELECT f.player_low_id, 'friend_link', f.updated_at, 100,
       'automatic', 'not_applicable', f.updated_at
FROM friendships f
WHERE f.status = 'accepted'
  AND EXISTS (SELECT 1 FROM achievement_definitions WHERE id = 'friend_link');

INSERT OR IGNORE INTO player_achievements (
  player_id, achievement_id, unlocked_at, progress, source,
  platform_mirror_status, updated_at
)
SELECT f.player_high_id, 'friend_link', f.updated_at, 100,
       'automatic', 'not_applicable', f.updated_at
FROM friendships f
WHERE f.status = 'accepted'
  AND EXISTS (SELECT 1 FROM achievement_definitions WHERE id = 'friend_link');

INSERT OR IGNORE INTO player_achievements (
  player_id, achievement_id, unlocked_at, progress, source,
  platform_mirror_status, updated_at
)
SELECT d.player_id, 'daily_streak_7', d.updated_at, 100,
       'automatic', 'not_applicable', d.updated_at
FROM daily_reward_state d
WHERE d.streak >= 7
  AND EXISTS (SELECT 1 FROM achievement_definitions WHERE id = 'daily_streak_7');

UPDATE players
SET achievement_count = (
  SELECT COUNT(*) FROM player_achievements pa WHERE pa.player_id = players.id
);

CREATE TABLE IF NOT EXISTS runtime_schema_state (
  schema_key TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  updated_at TEXT NOT NULL
);

INSERT INTO runtime_schema_state (schema_key, version, updated_at)
VALUES ('achievement_integrity', 1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
ON CONFLICT(schema_key) DO UPDATE SET
  version = excluded.version,
  updated_at = excluded.updated_at;
