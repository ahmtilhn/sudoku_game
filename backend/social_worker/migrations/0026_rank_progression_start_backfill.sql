PRAGMA foreign_keys = ON;

-- 0024 bootstrapped existing progression rows with migration time as started_at.
-- That can exclude legitimate rated matches played after the RP-system epoch but
-- before the migration/profile row was initialized. Only untouched progression
-- rows are moved backwards so already-settled RP history is never reordered.
UPDATE player_rank_progression
SET started_at = CASE
  WHEN (
    SELECT p.created_at
    FROM players p
    WHERE p.id = player_rank_progression.player_id
  ) > '2026-08-19T13:45:00.000Z'
  THEN (
    SELECT p.created_at
    FROM players p
    WHERE p.id = player_rank_progression.player_id
  )
  ELSE '2026-08-19T13:45:00.000Z'
END
WHERE ranked_games = 0
  AND NOT EXISTS (
    SELECT 1
    FROM rank_progression_settlements s
    WHERE s.player_id = player_rank_progression.player_id
  )
  AND started_at > CASE
    WHEN (
      SELECT p.created_at
      FROM players p
      WHERE p.id = player_rank_progression.player_id
    ) > '2026-08-19T13:45:00.000Z'
    THEN (
      SELECT p.created_at
      FROM players p
      WHERE p.id = player_rank_progression.player_id
    )
    ELSE '2026-08-19T13:45:00.000Z'
  END;
