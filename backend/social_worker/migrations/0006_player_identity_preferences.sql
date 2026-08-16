PRAGMA foreign_keys = ON;

ALTER TABLE players ADD COLUMN profile_confirmed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN discoverable INTEGER NOT NULL DEFAULT 1;
ALTER TABLE players ADD COLUMN name_source TEXT NOT NULL DEFAULT 'generated'
  CHECK(name_source IN ('generated', 'custom', 'google_play_games', 'game_center'));

CREATE INDEX players_discoverable_username_idx
  ON players(discoverable, username_normalized);

CREATE TRIGGER players_confirm_custom_name_after_insert AFTER INSERT ON players WHEN NEW.display_name != 'Sudoku Player' BEGIN UPDATE players SET profile_confirmed = 1, name_source = 'custom' WHERE id = NEW.id; END;

CREATE TRIGGER players_confirm_custom_name_after_update AFTER UPDATE OF display_name ON players WHEN NEW.display_name != OLD.display_name AND NEW.display_name != 'Sudoku Player' BEGIN UPDATE players SET profile_confirmed = 1, name_source = 'custom' WHERE id = NEW.id; END;
