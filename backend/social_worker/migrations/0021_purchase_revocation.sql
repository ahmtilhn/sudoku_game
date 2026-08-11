-- Refund, revocation and chargeback reconciliation.

ALTER TABLE purchase_grants
  ADD COLUMN revoked_at TEXT;

ALTER TABLE purchase_grants
  ADD COLUMN revocation_source TEXT;

ALTER TABLE purchase_grants
  ADD COLUMN refund_status TEXT NOT NULL DEFAULT 'none';

ALTER TABLE purchase_grants
  ADD COLUMN refunded_coins INTEGER NOT NULL DEFAULT 0;

ALTER TABLE purchase_grants
  ADD COLUMN unrecovered_coins INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_purchase_grants_refund_status
  ON purchase_grants(platform, refund_status, updated_at);

CREATE TABLE IF NOT EXISTS player_coin_debts (
  player_id TEXT PRIMARY KEY,
  amount INTEGER NOT NULL DEFAULT 0,
  reason TEXT NOT NULL,
  source_transaction_id TEXT,
  updated_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS store_notification_cursors (
  platform TEXT NOT NULL,
  cursor_key TEXT NOT NULL,
  cursor_value TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(platform, cursor_key)
);
