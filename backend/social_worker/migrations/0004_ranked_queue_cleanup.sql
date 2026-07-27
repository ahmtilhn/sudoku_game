PRAGMA foreign_keys = ON;

-- Matched queue rows are no longer needed after a room is created. Keeping
-- them allowed later searches to select a player who was already matched.
CREATE TRIGGER IF NOT EXISTS ranked_queue_cleanup_after_insert
AFTER INSERT ON ranked_queue
WHEN NEW.room_id IS NOT NULL
BEGIN
  DELETE FROM ranked_queue WHERE player_id = NEW.player_id;
END;

CREATE TRIGGER IF NOT EXISTS ranked_queue_cleanup_after_room_update
AFTER UPDATE OF room_id ON ranked_queue
WHEN NEW.room_id IS NOT NULL
BEGIN
  DELETE FROM ranked_queue WHERE player_id = NEW.player_id;
END;

-- Remove matched rows left by earlier Worker versions when this migration is
-- first applied. Active matches remain discoverable through the matches table.
DELETE FROM ranked_queue WHERE room_id IS NOT NULL;
