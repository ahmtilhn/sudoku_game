PRAGMA foreign_keys = ON;

-- D1 migrations execute SQL statements separately. Multi-statement trigger bodies
-- can be split into incomplete fragments, so queue maintenance stays in Worker
-- code and this migration only removes rows left by older deployments.

-- Active matches are discovered from the matches table, not ranked_queue.
DELETE FROM ranked_queue
WHERE room_id IS NOT NULL;

-- The Flutter client refreshes a live search periodically. A ten-minute-old
-- unmatched row represents a closed app, lost connection, or older Worker.
DELETE FROM ranked_queue
WHERE room_id IS NULL
  AND julianday(updated_at) < julianday('now', '-10 minutes');
