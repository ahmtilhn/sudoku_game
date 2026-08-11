PRAGMA foreign_keys = ON;

CREATE INDEX IF NOT EXISTS ranked_queue_open_match_idx
  ON ranked_queue(difficulty, room_id, updated_at, joined_at, rating)
  WHERE room_id IS NULL;

CREATE INDEX IF NOT EXISTS matches_active_player_a_idx
  ON matches(player_a_id, status, created_at DESC)
  WHERE status IN ('waiting', 'countdown', 'active', 'paused');

CREATE INDEX IF NOT EXISTS matches_active_player_b_idx
  ON matches(player_b_id, status, created_at DESC)
  WHERE status IN ('waiting', 'countdown', 'active', 'paused');

CREATE INDEX IF NOT EXISTS matches_history_player_a_idx
  ON matches(player_a_id, finished_at DESC, id)
  WHERE status IN ('completed', 'forfeited', 'cancelled', 'abandoned');

CREATE INDEX IF NOT EXISTS matches_history_player_b_idx
  ON matches(player_b_id, finished_at DESC, id)
  WHERE status IN ('completed', 'forfeited', 'cancelled', 'abandoned');

CREATE INDEX IF NOT EXISTS challenges_terminal_cleanup_idx
  ON challenges(status, updated_at)
  WHERE status IN ('declined', 'expired', 'cancelled', 'completed');

CREATE INDEX IF NOT EXISTS rematch_terminal_cleanup_idx
  ON rematch_invitations(status, updated_at)
  WHERE status IN ('accepted', 'declined', 'expired', 'cancelled', 'insufficient_coins');

CREATE INDEX IF NOT EXISTS request_limits_window_idx
  ON request_limits(window_started_at);

CREATE INDEX IF NOT EXISTS reward_claims_expired_cleanup_idx
  ON reward_claims(status, expires_at)
  WHERE status IN ('prepared', 'expired');

CREATE INDEX IF NOT EXISTS device_tokens_disabled_cleanup_idx
  ON device_tokens(enabled, updated_at)
  WHERE enabled = 0;

CREATE INDEX IF NOT EXISTS match_audit_retention_idx
  ON match_audit(event_timestamp);

PRAGMA optimize;
