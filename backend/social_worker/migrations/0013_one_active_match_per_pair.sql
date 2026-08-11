PRAGMA foreign_keys = ON;

-- A player pair may have only one live room. This is the final database guard
-- against duplicate rematch accepts, repeated challenge responses and retried
-- matchmaking requests creating two funded escrows for the same pair.
CREATE UNIQUE INDEX matches_one_active_pair_idx
ON matches (
  CASE WHEN player_a_id < player_b_id THEN player_a_id ELSE player_b_id END,
  CASE WHEN player_a_id < player_b_id THEN player_b_id ELSE player_a_id END
)
WHERE status IN ('waiting', 'countdown', 'active', 'paused');
