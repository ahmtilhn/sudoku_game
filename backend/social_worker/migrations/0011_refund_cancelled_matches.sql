PRAGMA foreign_keys = ON;

DROP TRIGGER IF EXISTS escrow_refund_draw_or_cancel;

CREATE TRIGGER escrow_refund_draw_or_cancel
AFTER UPDATE OF status ON matches
WHEN (
    NEW.status = 'cancelled'
    OR (NEW.status IN ('completed', 'abandoned') AND NEW.winner_id IS NULL)
  )
  AND EXISTS (
    SELECT 1 FROM match_coin_escrow
    WHERE match_id = NEW.id AND status = 'funded'
  )
BEGIN
  UPDATE players
  SET online_coins = online_coins + 100
  WHERE id IN (NEW.player_a_id, NEW.player_b_id);

  INSERT OR IGNORE INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  ) VALUES (
    lower(hex(randomblob(16))),
    NEW.player_a_id,
    100,
    (SELECT online_coins FROM players WHERE id = NEW.player_a_id),
    'match_refund',
    'match',
    NEW.id,
    'match_refund:' || NEW.id || ':' || NEW.player_a_id,
    json_object('entryFee', 100, 'terminalStatus', NEW.status),
    COALESCE(NEW.finished_at, NEW.updated_at)
  );

  INSERT OR IGNORE INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  ) VALUES (
    lower(hex(randomblob(16))),
    NEW.player_b_id,
    100,
    (SELECT online_coins FROM players WHERE id = NEW.player_b_id),
    'match_refund',
    'match',
    NEW.id,
    'match_refund:' || NEW.id || ':' || NEW.player_b_id,
    json_object('entryFee', 100, 'terminalStatus', NEW.status),
    COALESCE(NEW.finished_at, NEW.updated_at)
  );

  UPDATE match_coin_escrow
  SET status = 'refunded', winner_id = NULL,
      settled_at = COALESCE(NEW.finished_at, NEW.updated_at)
  WHERE match_id = NEW.id AND status = 'funded';
END;
