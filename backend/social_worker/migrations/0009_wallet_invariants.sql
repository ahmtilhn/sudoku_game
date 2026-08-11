PRAGMA foreign_keys = ON;

CREATE TRIGGER prevent_negative_player_coin_balance
BEFORE UPDATE OF online_coins ON players
WHEN NEW.online_coins < 0
BEGIN
  SELECT RAISE(ABORT, 'negative_coin_balance');
END;

-- createFundedMatch performs a guarded balance update immediately before each
-- immutable entry ledger row. Verify that the new balance is exactly 100 below
-- the latest ledger balance. If a guarded UPDATE affected zero rows, this aborts
-- and rolls the whole D1 batch back instead of creating a partially funded room.
CREATE TRIGGER validate_match_entry_ledger_before_insert
BEFORE INSERT ON coin_ledger
WHEN NEW.reason = 'match_entry'
  AND NEW.amount = -100
  AND NEW.balance_after != (
    COALESCE(
      (
        SELECT balance_after
        FROM coin_ledger
        WHERE player_id = NEW.player_id
          AND balance_after IS NOT NULL
        ORDER BY created_at DESC, rowid DESC
        LIMIT 1
      ),
      (SELECT online_coins + 100 FROM players WHERE id = NEW.player_id)
    ) - 100
  )
BEGIN
  SELECT RAISE(ABORT, 'match_entry_balance_invariant');
END;
