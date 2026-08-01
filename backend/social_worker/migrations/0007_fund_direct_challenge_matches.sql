PRAGMA foreign_keys = ON;

-- Direct friend challenges are still created by the original social route.
-- Fund them automatically when the accepted challenge inserts its match row.
CREATE TRIGGER fund_direct_challenge_match
AFTER INSERT ON matches
WHEN NEW.challenge_id IS NOT NULL
BEGIN
  SELECT CASE
    WHEN (SELECT online_coins FROM players WHERE id = NEW.player_a_id) < 100
      OR (SELECT online_coins FROM players WHERE id = NEW.player_b_id) < 100
    THEN RAISE(ABORT, 'insufficient_coins')
  END;

  UPDATE players
  SET online_coins = online_coins - 100, updated_at = NEW.created_at
  WHERE id = NEW.player_a_id;

  INSERT INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  ) VALUES (
    lower(hex(randomblob(16))),
    NEW.player_a_id,
    -100,
    (SELECT online_coins FROM players WHERE id = NEW.player_a_id),
    'match_entry',
    'match',
    NEW.id,
    'match_entry:' || NEW.id || ':' || NEW.player_a_id,
    json_object('entryFee', 100, 'pot', 200, 'source', 'direct_challenge'),
    NEW.created_at
  );

  UPDATE players
  SET online_coins = online_coins - 100, updated_at = NEW.created_at
  WHERE id = NEW.player_b_id;

  INSERT INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  ) VALUES (
    lower(hex(randomblob(16))),
    NEW.player_b_id,
    -100,
    (SELECT online_coins FROM players WHERE id = NEW.player_b_id),
    'match_entry',
    'match',
    NEW.id,
    'match_entry:' || NEW.id || ':' || NEW.player_b_id,
    json_object('entryFee', 100, 'pot', 200, 'source', 'direct_challenge'),
    NEW.created_at
  );

  INSERT INTO match_coin_escrow (
    match_id, player_a_id, player_b_id, player_a_amount,
    player_b_amount, pot_amount, status, funded_at
  ) VALUES (
    NEW.id, NEW.player_a_id, NEW.player_b_id,
    100, 100, 200, 'funded', NEW.created_at
  );
END;
