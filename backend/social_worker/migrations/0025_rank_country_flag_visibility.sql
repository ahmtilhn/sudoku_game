PRAGMA foreign_keys = ON;

-- Country itself already lives on players.country_code. Visibility is kept in
-- an additive preference table so a worker/schema rollout can safely create it
-- with IF NOT EXISTS and never risks a duplicate ALTER TABLE operation.
CREATE TABLE IF NOT EXISTS player_country_preferences (
  player_id TEXT PRIMARY KEY,
  country_flag_visible INTEGER NOT NULL DEFAULT 1
    CHECK(country_flag_visible IN (0, 1)),
  updated_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);
