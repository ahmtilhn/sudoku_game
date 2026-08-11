PRAGMA foreign_keys = ON;

ALTER TABLE challenges
  ADD COLUMN variant TEXT NOT NULL DEFAULT 'classic'
  CHECK(variant IN ('classic', 'samurai'));

ALTER TABLE matches
  ADD COLUMN variant TEXT NOT NULL DEFAULT 'classic'
  CHECK(variant IN ('classic', 'samurai'));

ALTER TABLE ranked_queue
  ADD COLUMN variant TEXT NOT NULL DEFAULT 'classic'
  CHECK(variant IN ('classic', 'samurai'));

DROP INDEX IF EXISTS ranked_queue_difficulty_rating_idx;
CREATE INDEX ranked_queue_variant_difficulty_rating_idx
  ON ranked_queue(variant, difficulty, rating, joined_at);

CREATE INDEX matches_variant_status_idx
  ON matches(variant, status, updated_at DESC);
