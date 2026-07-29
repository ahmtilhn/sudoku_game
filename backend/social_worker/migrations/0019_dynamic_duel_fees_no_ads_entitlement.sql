PRAGMA foreign_keys = OFF;

DROP TRIGGER IF EXISTS escrow_prepare_winner_payout;
DROP TRIGGER IF EXISTS escrow_ignore_legacy_winner_update;
DROP TRIGGER IF EXISTS escrow_ignore_legacy_loser_update;
DROP TRIGGER IF EXISTS escrow_refund_draw_or_cancel;
DROP TRIGGER IF EXISTS fund_direct_challenge_match;

ALTER TABLE match_coin_settlements RENAME TO match_coin_settlements_0019_old;

CREATE TABLE match_coin_settlements (
  match_id TEXT PRIMARY KEY,
  winner_id TEXT NOT NULL,
  loser_id TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK(amount > 0),
  applied_at TEXT NOT NULL,
  winner_balance_after INTEGER,
  loser_balance_after INTEGER,
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE,
  FOREIGN KEY(winner_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(loser_id) REFERENCES players(id) ON DELETE CASCADE
);

INSERT INTO match_coin_settlements (
  match_id, winner_id, loser_id, amount, applied_at,
  winner_balance_after, loser_balance_after
)
SELECT match_id, winner_id, loser_id, amount, applied_at,
       winner_balance_after, loser_balance_after
FROM match_coin_settlements_0019_old;

DROP TABLE match_coin_settlements_0019_old;

ALTER TABLE match_coin_escrow RENAME TO match_coin_escrow_0019_old;

CREATE TABLE match_coin_escrow (
  match_id TEXT PRIMARY KEY,
  player_a_id TEXT NOT NULL,
  player_b_id TEXT NOT NULL,
  player_a_amount INTEGER NOT NULL CHECK(player_a_amount > 0),
  player_b_amount INTEGER NOT NULL CHECK(player_b_amount > 0),
  pot_amount INTEGER NOT NULL CHECK(pot_amount = player_a_amount + player_b_amount),
  status TEXT NOT NULL CHECK(status IN ('funded', 'paid', 'refunded', 'cancelled')),
  winner_id TEXT,
  funded_at TEXT NOT NULL,
  settled_at TEXT,
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE,
  FOREIGN KEY(player_a_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(player_b_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(winner_id) REFERENCES players(id) ON DELETE SET NULL
);

INSERT INTO match_coin_escrow (
  match_id, player_a_id, player_b_id, player_a_amount,
  player_b_amount, pot_amount, status, winner_id, funded_at, settled_at
)
SELECT match_id, player_a_id, player_b_id, player_a_amount,
       player_b_amount, pot_amount, status, winner_id, funded_at, settled_at
FROM match_coin_escrow_0019_old;

DROP TABLE match_coin_escrow_0019_old;

CREATE TABLE IF NOT EXISTS player_entitlements (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  entitlement_key TEXT NOT NULL CHECK(entitlement_key IN ('no_ads')),
  source_platform TEXT NOT NULL CHECK(source_platform IN ('android', 'ios', 'admin')),
  source_product_id TEXT NOT NULL,
  source_transaction_id TEXT,
  verification_hash TEXT,
  granted_at TEXT NOT NULL,
  revoked_at TEXT,
  updated_at TEXT NOT NULL,
  UNIQUE(player_id, entitlement_key),
  UNIQUE(source_transaction_id),
  UNIQUE(verification_hash),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS player_entitlements_player_idx
  ON player_entitlements(player_id, entitlement_key, revoked_at);

CREATE TRIGGER escrow_prepare_winner_payout
AFTER INSERT ON match_coin_settlements
WHEN EXISTS (
  SELECT 1 FROM match_coin_escrow
  WHERE match_id = NEW.match_id AND status = 'funded'
)
BEGIN
  INSERT OR IGNORE INTO match_coin_intercepts (
    match_id, winner_id, loser_id, created_at
  ) VALUES (NEW.match_id, NEW.winner_id, NEW.loser_id, NEW.applied_at);

  UPDATE players
  SET online_coins = online_coins + (
    SELECT pot_amount FROM match_coin_escrow WHERE match_id = NEW.match_id
  )
  WHERE id = NEW.winner_id;

  INSERT OR IGNORE INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  ) VALUES (
    lower(hex(randomblob(16))),
    NEW.winner_id,
    (SELECT pot_amount FROM match_coin_escrow WHERE match_id = NEW.match_id),
    (SELECT online_coins FROM players WHERE id = NEW.winner_id),
    'match_payout',
    'match',
    NEW.match_id,
    'match_payout:' || NEW.match_id,
    json_object(
      'pot', (SELECT pot_amount FROM match_coin_escrow WHERE match_id = NEW.match_id),
      'entryFee', (SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.match_id)
    ),
    NEW.applied_at
  );

  UPDATE match_coin_escrow
  SET status = 'paid', winner_id = NEW.winner_id, settled_at = NEW.applied_at
  WHERE match_id = NEW.match_id AND status = 'funded';
END;

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
  SET online_coins = online_coins + (
    SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id
  )
  WHERE id = NEW.player_a_id;

  UPDATE players
  SET online_coins = online_coins + (
    SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id
  )
  WHERE id = NEW.player_b_id;

  INSERT OR IGNORE INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  ) VALUES (
    lower(hex(randomblob(16))),
    NEW.player_a_id,
    (SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id),
    (SELECT online_coins FROM players WHERE id = NEW.player_a_id),
    'match_refund',
    'match',
    NEW.id,
    'match_refund:' || NEW.id || ':' || NEW.player_a_id,
    json_object(
      'entryFee', (SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id),
      'terminalStatus', NEW.status
    ),
    COALESCE(NEW.finished_at, NEW.updated_at)
  );

  INSERT OR IGNORE INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  ) VALUES (
    lower(hex(randomblob(16))),
    NEW.player_b_id,
    (SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id),
    (SELECT online_coins FROM players WHERE id = NEW.player_b_id),
    'match_refund',
    'match',
    NEW.id,
    'match_refund:' || NEW.id || ':' || NEW.player_b_id,
    json_object(
      'entryFee', (SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id),
      'terminalStatus', NEW.status
    ),
    COALESCE(NEW.finished_at, NEW.updated_at)
  );

  UPDATE match_coin_escrow
  SET status = 'refunded', winner_id = NULL,
      settled_at = COALESCE(NEW.finished_at, NEW.updated_at)
  WHERE match_id = NEW.id AND status = 'funded';
END;

CREATE TRIGGER fund_direct_challenge_match
AFTER INSERT ON matches
WHEN NEW.challenge_id IS NOT NULL
BEGIN
  INSERT INTO match_coin_escrow (
    match_id, player_a_id, player_b_id, player_a_amount,
    player_b_amount, pot_amount, status, funded_at
  )
  SELECT NEW.id, NEW.player_a_id, NEW.player_b_id,
         CASE NEW.difficulty
           WHEN 'beginner' THEN 100
           WHEN 'easy' THEN 150
           WHEN 'medium' THEN 250
           WHEN 'hard' THEN 400
           WHEN 'expert' THEN 650
         END,
         CASE NEW.difficulty
           WHEN 'beginner' THEN 100
           WHEN 'easy' THEN 150
           WHEN 'medium' THEN 250
           WHEN 'hard' THEN 400
           WHEN 'expert' THEN 650
         END,
         CASE NEW.difficulty
           WHEN 'beginner' THEN 200
           WHEN 'easy' THEN 300
           WHEN 'medium' THEN 500
           WHEN 'hard' THEN 800
           WHEN 'expert' THEN 1300
         END,
         'funded',
         NEW.created_at
  WHERE (SELECT online_coins FROM players WHERE id = NEW.player_a_id) >=
        CASE NEW.difficulty
          WHEN 'beginner' THEN 100
          WHEN 'easy' THEN 150
          WHEN 'medium' THEN 250
          WHEN 'hard' THEN 400
          WHEN 'expert' THEN 650
        END
    AND (SELECT online_coins FROM players WHERE id = NEW.player_b_id) >=
        CASE NEW.difficulty
          WHEN 'beginner' THEN 100
          WHEN 'easy' THEN 150
          WHEN 'medium' THEN 250
          WHEN 'hard' THEN 400
          WHEN 'expert' THEN 650
        END;

  UPDATE challenges
  SET status = 'cancelled', room_id = NULL, updated_at = NEW.created_at
  WHERE id = NEW.challenge_id
    AND NOT EXISTS (
      SELECT 1 FROM match_coin_escrow WHERE match_id = NEW.id
    );

  UPDATE matches
  SET status = 'cancelled', winner_id = NULL,
      finish_reason = 'insufficient_coins',
      finished_at = NEW.created_at, updated_at = NEW.created_at
  WHERE id = NEW.id
    AND NOT EXISTS (
      SELECT 1 FROM match_coin_escrow WHERE match_id = NEW.id
    );

  UPDATE players
  SET online_coins = online_coins - (
    SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id
  ), updated_at = NEW.created_at
  WHERE id = NEW.player_a_id
    AND EXISTS (
      SELECT 1 FROM match_coin_escrow
      WHERE match_id = NEW.id AND status = 'funded'
    );

  INSERT INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  )
  SELECT lower(hex(randomblob(16))),
         NEW.player_a_id,
         -player_a_amount,
         (SELECT online_coins FROM players WHERE id = NEW.player_a_id),
         'match_entry',
         'match',
         NEW.id,
         'match_entry:' || NEW.id || ':' || NEW.player_a_id,
         json_object('entryFee', player_a_amount, 'pot', pot_amount, 'source', 'direct_challenge'),
         NEW.created_at
  FROM match_coin_escrow
  WHERE match_id = NEW.id AND status = 'funded';

  UPDATE players
  SET online_coins = online_coins - (
    SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id
  ), updated_at = NEW.created_at
  WHERE id = NEW.player_b_id
    AND EXISTS (
      SELECT 1 FROM match_coin_escrow
      WHERE match_id = NEW.id AND status = 'funded'
    );

  INSERT INTO coin_ledger (
    id, player_id, amount, balance_after, reason,
    reference_type, reference_id, idempotency_key, metadata_json, created_at
  )
  SELECT lower(hex(randomblob(16))),
         NEW.player_b_id,
         -player_b_amount,
         (SELECT online_coins FROM players WHERE id = NEW.player_b_id),
         'match_entry',
         'match',
         NEW.id,
         'match_entry:' || NEW.id || ':' || NEW.player_b_id,
         json_object('entryFee', player_b_amount, 'pot', pot_amount, 'source', 'direct_challenge'),
         NEW.created_at
  FROM match_coin_escrow
  WHERE match_id = NEW.id AND status = 'funded';
END;

PRAGMA foreign_keys = ON;
