PRAGMA foreign_keys = ON;

-- Country is an explicit player profile choice. Keep the selected ISO country
-- code even when the player hides the flag so the preference can be toggled
-- without losing the selection.
ALTER TABLE players ADD COLUMN country_flag_visible INTEGER NOT NULL DEFAULT 1
  CHECK(country_flag_visible IN (0, 1));
