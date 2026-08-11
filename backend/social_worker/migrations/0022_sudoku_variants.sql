PRAGMA foreign_keys = ON;

ALTER TABLE matches
  ADD COLUMN variant TEXT NOT NULL DEFAULT 'classic9'
  CHECK(variant IN ('classic9', 'classic16'));
ALTER TABLE matches
  ADD COLUMN board_size INTEGER NOT NULL DEFAULT 9
  CHECK(board_size IN (9, 16));
ALTER TABLE matches
  ADD COLUMN cell_count INTEGER NOT NULL DEFAULT 81
  CHECK(cell_count IN (81, 256));

ALTER TABLE challenges
  ADD COLUMN variant TEXT NOT NULL DEFAULT 'classic9'
  CHECK(variant IN ('classic9', 'classic16'));

ALTER TABLE ranked_queue
  ADD COLUMN variant TEXT NOT NULL DEFAULT 'classic9'
  CHECK(variant IN ('classic9', 'classic16'));

ALTER TABLE rematch_invitations
  ADD COLUMN variant TEXT NOT NULL DEFAULT 'classic9'
  CHECK(variant IN ('classic9', 'classic16'));

DROP INDEX IF EXISTS ranked_queue_difficulty_rating_idx;
CREATE INDEX ranked_queue_variant_difficulty_rating_idx
  ON ranked_queue(variant, difficulty, rating, joined_at);

CREATE INDEX matches_variant_difficulty_status_idx
  ON matches(variant, difficulty, status, updated_at DESC);

CREATE INDEX challenges_recipient_variant_status_idx
  ON challenges(recipient_id, variant, status, created_at DESC);

CREATE TABLE player_variant_ratings (
  player_id TEXT NOT NULL,
  variant TEXT NOT NULL CHECK(variant IN ('classic9', 'classic16')),
  scope TEXT NOT NULL CHECK(scope IN ('global', 'beginner', 'easy', 'medium', 'hard', 'expert')),
  rating INTEGER NOT NULL DEFAULT 1000,
  games_played INTEGER NOT NULL DEFAULT 0,
  wins INTEGER NOT NULL DEFAULT 0,
  losses INTEGER NOT NULL DEFAULT 0,
  draws INTEGER NOT NULL DEFAULT 0,
  win_streak INTEGER NOT NULL DEFAULT 0,
  best_rating INTEGER NOT NULL DEFAULT 1000,
  provisional_games INTEGER NOT NULL DEFAULT 20,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_id, variant, scope),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX player_variant_ratings_leaderboard_idx
  ON player_variant_ratings(variant, scope, rating DESC, games_played DESC, updated_at ASC);

INSERT OR IGNORE INTO player_variant_ratings (
  player_id,
  variant,
  scope,
  rating,
  games_played,
  wins,
  losses,
  draws,
  win_streak,
  best_rating,
  provisional_games,
  updated_at
)
SELECT
  player_id,
  'classic9',
  scope,
  rating,
  games_played,
  wins,
  losses,
  draws,
  win_streak,
  best_rating,
  provisional_games,
  updated_at
FROM player_ratings;
