-- Store purchase lifecycle hardening.
-- Apply before deploying Worker code that writes acknowledgement metadata.

ALTER TABLE purchase_grants
  ADD COLUMN acknowledged_at TEXT;

ALTER TABLE purchase_grants
  ADD COLUMN acknowledge_status TEXT NOT NULL DEFAULT 'not_required';

ALTER TABLE purchase_grants
  ADD COLUMN acknowledge_error TEXT;

CREATE INDEX IF NOT EXISTS idx_purchase_grants_acknowledge_retry
  ON purchase_grants(platform, product_id, acknowledge_status, updated_at);

CREATE TABLE IF NOT EXISTS purchase_events (
  id TEXT PRIMARY KEY,
  platform TEXT NOT NULL,
  event_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  transaction_id TEXT,
  product_id TEXT,
  player_id TEXT,
  status TEXT NOT NULL DEFAULT 'received',
  payload_hash TEXT NOT NULL,
  payload_json TEXT,
  processed_at TEXT,
  error_code TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(platform, event_id),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_purchase_events_transaction
  ON purchase_events(platform, transaction_id, created_at DESC);

CREATE TABLE IF NOT EXISTS entitlement_events (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  entitlement_key TEXT NOT NULL,
  action TEXT NOT NULL,
  source TEXT NOT NULL,
  source_event_id TEXT,
  source_transaction_id TEXT,
  metadata_json TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(source, source_event_id, action),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_entitlement_events_player
  ON entitlement_events(player_id, entitlement_key, created_at DESC);

CREATE TABLE IF NOT EXISTS reconciliation_runs (
  id TEXT PRIMARY KEY,
  platform TEXT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  cursor TEXT,
  scanned_count INTEGER NOT NULL DEFAULT 0,
  changed_count INTEGER NOT NULL DEFAULT 0,
  error_count INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT,
  started_at TEXT NOT NULL,
  completed_at TEXT,
  updated_at TEXT NOT NULL
);
