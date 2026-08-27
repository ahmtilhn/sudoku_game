PRAGMA foreign_keys = OFF;

DROP INDEX IF EXISTS purchase_grants_player_idx;
DROP INDEX IF EXISTS purchase_grants_store_order_idx;
DROP INDEX IF EXISTS idx_purchase_grants_acknowledge_retry;
DROP INDEX IF EXISTS idx_purchase_grants_refund_status;

ALTER TABLE purchase_grants
RENAME TO purchase_grants_0028_old;

CREATE TABLE purchase_grants (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('android', 'ios')),
  product_id TEXT NOT NULL,
  transaction_id TEXT NOT NULL UNIQUE,
  verification_hash TEXT NOT NULL UNIQUE,

  coins INTEGER NOT NULL CHECK(
    (
      product_id IN ('no_ads', 'sudoku_duel_no_ads')
      AND coins = 0
    )
    OR
    (
      product_id NOT IN ('no_ads', 'sudoku_duel_no_ads')
      AND coins IN (
        100, 500, 1000, 5000, 10000, 50000, 100000
      )
    )
  ),

  status TEXT NOT NULL CHECK(
    status IN ('verified', 'refunded', 'revoked')
  ),

  purchased_at TEXT,
  granted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,

  store_environment TEXT,
  store_order_id TEXT,
  consumed_at TEXT,
  verification_source TEXT,

  acknowledged_at TEXT,
  acknowledge_status TEXT NOT NULL DEFAULT 'not_required',
  acknowledge_error TEXT,

  revoked_at TEXT,
  revocation_source TEXT,

  refund_status TEXT NOT NULL DEFAULT 'none',
  refunded_coins INTEGER NOT NULL DEFAULT 0,
  unrecovered_coins INTEGER NOT NULL DEFAULT 0,

  FOREIGN KEY(player_id)
    REFERENCES players(id)
    ON DELETE CASCADE
);

INSERT INTO purchase_grants (
  id,
  player_id,
  platform,
  product_id,
  transaction_id,
  verification_hash,
  coins,
  status,
  purchased_at,
  granted_at,
  updated_at,
  store_environment,
  store_order_id,
  consumed_at,
  verification_source,
  acknowledged_at,
  acknowledge_status,
  acknowledge_error,
  revoked_at,
  revocation_source,
  refund_status,
  refunded_coins,
  unrecovered_coins
)
SELECT
  id,
  player_id,
  platform,
  product_id,
  transaction_id,
  verification_hash,
  coins,
  status,
  purchased_at,
  granted_at,
  updated_at,
  store_environment,
  store_order_id,
  consumed_at,
  verification_source,
  acknowledged_at,
  acknowledge_status,
  acknowledge_error,
  revoked_at,
  revocation_source,
  refund_status,
  refunded_coins,
  unrecovered_coins
FROM purchase_grants_0028_old;

DROP TABLE purchase_grants_0028_old;

CREATE INDEX purchase_grants_player_idx
  ON purchase_grants(player_id, granted_at DESC);

CREATE INDEX purchase_grants_store_order_idx
  ON purchase_grants(store_order_id)
  WHERE store_order_id IS NOT NULL;

CREATE INDEX idx_purchase_grants_acknowledge_retry
  ON purchase_grants(
    platform,
    product_id,
    acknowledge_status,
    updated_at
  );

CREATE INDEX idx_purchase_grants_refund_status
  ON purchase_grants(
    platform,
    refund_status,
    updated_at
  );

PRAGMA foreign_keys = ON;
