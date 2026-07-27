PRAGMA foreign_keys = ON;

ALTER TABLE players ADD COLUMN profile_confirmed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN discoverable INTEGER NOT NULL DEFAULT 1;
ALTER TABLE players ADD COLUMN name_source TEXT NOT NULL DEFAULT 'generated'
  CHECK(name_source IN ('generated', 'custom', 'google_play_games', 'game_center'));

CREATE INDEX players_discoverable_username_idx
  ON players(discoverable, username_normalized);
