-- Economy V3: progressive daily rewards, career budget, hint refills and duel recovery.
-- Existing coin_ledger/reward_claims remain intact for backwards data compatibility.
-- V3 uses its own idempotent event tables and mirrors every coin delta into coin_ledger.

CREATE TABLE IF NOT EXISTS economy_v3_daily_state (
  player_id TEXT PRIMARY KEY,
  claims_total INTEGER NOT NULL DEFAULT 0 CHECK(claims_total >= 0),
  last_claim_day TEXT,
  last_claim_sequence INTEGER NOT NULL DEFAULT 0 CHECK(last_claim_sequence >= 0),
  last_claim_amount INTEGER NOT NULL DEFAULT 0 CHECK(last_claim_amount >= 0),
  doubled_sequence INTEGER NOT NULL DEFAULT 0 CHECK(doubled_sequence >= 0),
  updated_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS economy_v3_inventory (
  player_id TEXT PRIMARY KEY,
  hint_refills INTEGER NOT NULL DEFAULT 0 CHECK(hint_refills >= 0),
  updated_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS economy_v3_inventory_events (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  source TEXT NOT NULL,
  reference_id TEXT NOT NULL,
  refill_delta INTEGER NOT NULL CHECK(refill_delta != 0),
  created_at TEXT NOT NULL,
  UNIQUE(player_id, source, reference_id),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TRIGGER IF NOT EXISTS economy_v3_inventory_event_apply AFTER INSERT ON economy_v3_inventory_events BEGIN INSERT INTO economy_v3_inventory (player_id, hint_refills, updated_at) VALUES (NEW.player_id, MAX(0, NEW.refill_delta), NEW.created_at) ON CONFLICT(player_id) DO UPDATE SET hint_refills = MAX(0, economy_v3_inventory.hint_refills + NEW.refill_delta), updated_at = excluded.updated_at; END;

CREATE TABLE IF NOT EXISTS economy_v3_coin_events (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  source TEXT NOT NULL,
  reference_id TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK(amount != 0),
  ledger_reason TEXT NOT NULL CHECK(ledger_reason IN (
    'daily_login',
    'daily_rewarded_ad',
    'career_rewarded_ad',
    'achievement_reward',
    'career_continue'
  )),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  UNIQUE(player_id, source, reference_id),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TRIGGER IF NOT EXISTS economy_v3_coin_event_balance_guard BEFORE INSERT ON economy_v3_coin_events WHEN NEW.amount < 0 BEGIN SELECT RAISE(ABORT, 'insufficient_coins') WHERE COALESCE((SELECT online_coins FROM players WHERE id = NEW.player_id), 0) + NEW.amount < 0; END;

CREATE TRIGGER IF NOT EXISTS economy_v3_coin_event_apply AFTER INSERT ON economy_v3_coin_events BEGIN UPDATE players SET online_coins = online_coins + NEW.amount, updated_at = NEW.created_at WHERE id = NEW.player_id; INSERT OR IGNORE INTO coin_ledger ( id, player_id, amount, balance_after, reason, reference_type, reference_id, idempotency_key, metadata_json, created_at ) VALUES ( lower(hex(randomblob(16))), NEW.player_id, NEW.amount, (SELECT online_coins FROM players WHERE id = NEW.player_id), NEW.ledger_reason, 'economy_v3', NEW.reference_id, 'economy_v3:' || NEW.player_id || ':' || NEW.source || ':' || NEW.reference_id, json_patch(COALESCE(NEW.metadata_json, '{}'), json_object('economySource', NEW.source)), NEW.created_at ); END;

CREATE INDEX IF NOT EXISTS economy_v3_coin_events_player_time_idx
  ON economy_v3_coin_events(player_id, created_at DESC);

CREATE TABLE IF NOT EXISTS economy_v3_career_progress (
  player_id TEXT NOT NULL,
  variant TEXT NOT NULL,
  highest_rewarded_level INTEGER NOT NULL DEFAULT 0 CHECK(highest_rewarded_level >= 0),
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_id, variant),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS economy_v3_career_daily (
  player_id TEXT NOT NULL,
  day_key TEXT NOT NULL,
  coins_earned INTEGER NOT NULL DEFAULT 0 CHECK(coins_earned >= 0),
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_id, day_key),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS economy_v3_recovery_daily (
  player_id TEXT NOT NULL,
  day_key TEXT NOT NULL,
  coins_earned INTEGER NOT NULL DEFAULT 0 CHECK(coins_earned >= 0),
  popup_count INTEGER NOT NULL DEFAULT 0 CHECK(popup_count >= 0),
  last_popup_at TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_id, day_key),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS economy_v3_recovery_matches (
  player_id TEXT NOT NULL,
  match_id TEXT NOT NULL,
  trigger_kind TEXT NOT NULL CHECK(trigger_kind IN ('large_loss', 'balance_shock', 'broke')),
  offered_amount INTEGER NOT NULL CHECK(offered_amount BETWEEN 25 AND 75),
  status TEXT NOT NULL CHECK(status IN ('prepared', 'claimed', 'dismissed', 'expired')),
  verification_token TEXT,
  created_at TEXT NOT NULL,
  claimed_at TEXT,
  PRIMARY KEY(player_id, match_id),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS economy_v3_recovery_match_status_idx
  ON economy_v3_recovery_matches(player_id, status, created_at DESC);
