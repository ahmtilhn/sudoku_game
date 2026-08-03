PRAGMA foreign_keys = ON;

-- The application currently creates a one-time 1,000 Coin starter ledger row and
-- then applies that amount to the player balance. Production accounts must start
-- with 10,000 Coins. This trigger adds the 9,000 Coin difference before the
-- application applies its existing 1,000 Coin update, so the final balance and
-- ledger entry are both exactly 10,000 Coins.
--
-- Existing accounts are not changed because their idempotent starter_grant row
-- already exists and this trigger only runs after a new row is inserted.
CREATE TRIGGER IF NOT EXISTS starter_grant_upgrade_to_10000
AFTER INSERT ON coin_ledger
WHEN NEW.reason = 'starter_grant' AND NEW.amount = 1000
BEGIN
  UPDATE players
  SET online_coins = online_coins + 9000
  WHERE id = NEW.player_id;

  UPDATE coin_ledger
  SET amount = 10000,
      metadata_json = json_set(
        COALESCE(metadata_json, '{}'),
        '$.starterCoins',
        10000
      )
  WHERE id = NEW.id;
END;
