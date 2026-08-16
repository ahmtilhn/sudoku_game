PRAGMA foreign_keys = ON;

CREATE TABLE deleted_accounts (
  firebase_uid TEXT PRIMARY KEY,
  player_id TEXT,
  requested_at TEXT NOT NULL,
  completed_at TEXT,
  reason TEXT NOT NULL DEFAULT 'user_request'
);

CREATE INDEX deleted_accounts_requested_idx
  ON deleted_accounts(requested_at DESC);

CREATE TRIGGER prevent_deleted_account_recreation BEFORE INSERT ON players WHEN EXISTS ( SELECT 1 FROM deleted_accounts d WHERE d.firebase_uid = NEW.firebase_uid ) BEGIN SELECT RAISE(ABORT, 'account_deleted'); END;
