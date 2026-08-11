PRAGMA foreign_keys = ON;

ALTER TABLE players ADD COLUMN country_code TEXT;
ALTER TABLE players ADD COLUMN season_peak_rating INTEGER NOT NULL DEFAULT 1000;
ALTER TABLE players ADD COLUMN tournament_entries INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN tournament_podiums INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN country_contributions INTEGER NOT NULL DEFAULT 0;

CREATE TABLE achievement_definitions (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL CHECK(category IN ('ranked', 'tournament', 'country', 'sudoku', 'social', 'season')),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  tier TEXT NOT NULL,
  reward_amount INTEGER NOT NULL DEFAULT 0,
  platform_mirror_key TEXT,
  platform_mirror_enabled INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE player_achievements (
  player_id TEXT NOT NULL,
  achievement_id TEXT NOT NULL,
  unlocked_at TEXT NOT NULL,
  progress INTEGER NOT NULL DEFAULT 100,
  source TEXT NOT NULL DEFAULT 'server',
  platform_mirror_status TEXT NOT NULL DEFAULT 'pending'
    CHECK(platform_mirror_status IN ('not_applicable', 'pending', 'synced', 'failed')),
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_id, achievement_id),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(achievement_id) REFERENCES achievement_definitions(id) ON DELETE CASCADE
);

CREATE INDEX player_achievements_player_unlocked_idx
  ON player_achievements(player_id, unlocked_at DESC);

CREATE TABLE achievement_showcase (
  player_id TEXT NOT NULL,
  achievement_id TEXT NOT NULL,
  slot INTEGER NOT NULL CHECK(slot BETWEEN 1 AND 3),
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_id, slot),
  UNIQUE(player_id, achievement_id),
  FOREIGN KEY(player_id, achievement_id)
    REFERENCES player_achievements(player_id, achievement_id) ON DELETE CASCADE
);

CREATE TABLE platform_achievement_mirror_queue (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  achievement_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('google_play_games', 'game_center')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending', 'synced', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(player_id, achievement_id, platform),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(achievement_id) REFERENCES achievement_definitions(id) ON DELETE CASCADE
);

CREATE INDEX platform_achievement_mirror_due_idx
  ON platform_achievement_mirror_queue(status, next_attempt_at);

CREATE TABLE daily_reward_state (
  player_id TEXT PRIMARY KEY,
  streak INTEGER NOT NULL DEFAULT 0,
  last_claim_utc_day TEXT,
  grace_until_utc_day TEXT,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX player_ratings_stable_leaderboard_idx
  ON player_ratings(scope, rating DESC, games_played DESC, wins DESC, draws DESC, updated_at ASC, player_id ASC);

INSERT OR IGNORE INTO achievement_definitions (
  id, category, title, description, tier, reward_amount,
  platform_mirror_key, platform_mirror_enabled, sort_order
) VALUES
  ('first_win', 'ranked', 'First Duel Win', 'Win your first online duel.', 'bronze', 50, 'first_win', 1, 10),
  ('wins_10', 'ranked', 'Ten Duel Wins', 'Win 10 online duels.', 'silver', 100, 'wins_10', 1, 20),
  ('games_25', 'ranked', 'Twenty Five Duels', 'Finish 25 online duels.', 'silver', 100, NULL, 0, 30),
  ('wins_50', 'ranked', 'Fifty Duel Wins', 'Win 50 online duels.', 'gold', 250, 'wins_50', 1, 40),
  ('rating_1200', 'season', 'Rising Rating', 'Reach 1200 ELO.', 'gold', 250, 'rating_1200', 1, 50),
  ('rating_1500', 'season', 'Elite Rating', 'Reach 1500 ELO.', 'platinum', 500, 'rating_1500', 1, 60),
  ('wins_250', 'ranked', 'Duel Legend', 'Win 250 online duels.', 'milestone', 1000, NULL, 0, 70),
  ('daily_streak_7', 'sudoku', 'Seven Day Focus', 'Claim daily rewards for a 7 day streak.', 'silver', 0, NULL, 0, 80),
  ('country_contributor', 'country', 'Country Contributor', 'Contribute points for your country.', 'bronze', 0, NULL, 0, 90),
  ('tournament_podium', 'tournament', 'Podium Finish', 'Finish on a tournament podium.', 'gold', 0, NULL, 0, 100),
  ('friend_link', 'social', 'Friendly Rival', 'Add an in-game friend.', 'bronze', 0, NULL, 0, 110);

INSERT OR IGNORE INTO player_achievements (
  player_id, achievement_id, unlocked_at, progress, source,
  platform_mirror_status, updated_at
)
SELECT p.id, d.id, COALESCE(rc.claimed_at, rc.prepared_at, p.updated_at),
       100, 'server',
       CASE WHEN d.platform_mirror_enabled = 1 THEN 'pending' ELSE 'not_applicable' END,
       COALESCE(rc.claimed_at, rc.prepared_at, p.updated_at)
FROM reward_claims rc
JOIN players p ON p.id = rc.player_id
JOIN achievement_definitions d ON d.id = rc.reward_key
WHERE rc.reward_type = 'achievement_reward'
  AND rc.status = 'claimed';

INSERT OR IGNORE INTO platform_achievement_mirror_queue (
  id, player_id, achievement_id, platform, status, attempts,
  next_attempt_at, created_at, updated_at
)
SELECT lower(hex(randomblob(16))), pa.player_id, pa.achievement_id,
       platform.value, 'pending', 0, pa.unlocked_at, pa.unlocked_at, pa.updated_at
FROM player_achievements pa
JOIN achievement_definitions d ON d.id = pa.achievement_id
JOIN (
  SELECT 'google_play_games' AS value
  UNION ALL
  SELECT 'game_center' AS value
) platform
WHERE d.platform_mirror_enabled = 1;
