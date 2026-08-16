PRAGMA foreign_keys = ON;

CREATE TABLE coin_ledger (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  amount INTEGER NOT NULL,
  balance_after INTEGER,
  reason TEXT NOT NULL CHECK(reason IN (
    'starter_grant',
    'match_entry',
    'match_payout',
    'match_refund',
    'daily_login',
    'daily_rewarded_ad',
    'career_rewarded_ad',
    'achievement_reward',
    'career_continue',
    'hint_purchase',
    'store_purchase',
    'purchase_refund',
    'admin_adjustment'
  )),
  reference_type TEXT,
  reference_id TEXT,
  idempotency_key TEXT NOT NULL UNIQUE,
  metadata_json TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX coin_ledger_player_created_idx
  ON coin_ledger(player_id, created_at DESC);

CREATE TABLE match_coin_escrow (
  match_id TEXT PRIMARY KEY,
  player_a_id TEXT NOT NULL,
  player_b_id TEXT NOT NULL,
  player_a_amount INTEGER NOT NULL CHECK(player_a_amount = 100),
  player_b_amount INTEGER NOT NULL CHECK(player_b_amount = 100),
  pot_amount INTEGER NOT NULL CHECK(pot_amount = 200),
  status TEXT NOT NULL CHECK(status IN ('funded', 'paid', 'refunded')),
  winner_id TEXT,
  funded_at TEXT NOT NULL,
  settled_at TEXT,
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE,
  FOREIGN KEY(player_a_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(player_b_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(winner_id) REFERENCES players(id) ON DELETE SET NULL
);

CREATE TABLE match_coin_intercepts (
  match_id TEXT PRIMARY KEY,
  winner_id TEXT NOT NULL,
  loser_id TEXT NOT NULL,
  winner_update_pending INTEGER NOT NULL DEFAULT 1,
  loser_update_pending INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE,
  FOREIGN KEY(winner_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(loser_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE TABLE reward_claims (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  reward_type TEXT NOT NULL CHECK(reward_type IN (
    'daily_login',
    'daily_rewarded_ad',
    'career_rewarded_ad',
    'achievement_reward'
  )),
  reward_key TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK(amount > 0),
  status TEXT NOT NULL CHECK(status IN ('prepared', 'claimed', 'expired')),
  verification_token TEXT,
  prepared_at TEXT NOT NULL,
  claimed_at TEXT,
  expires_at TEXT,
  UNIQUE(player_id, reward_type, reward_key),
  UNIQUE(verification_token),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX reward_claims_player_type_idx
  ON reward_claims(player_id, reward_type, prepared_at DESC);

CREATE TABLE purchase_grants (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('android', 'ios')),
  product_id TEXT NOT NULL,
  transaction_id TEXT NOT NULL UNIQUE,
  verification_hash TEXT NOT NULL UNIQUE,
  coins INTEGER NOT NULL CHECK(coins IN (100, 500, 1000, 5000, 10000, 50000, 100000)),
  status TEXT NOT NULL CHECK(status IN ('verified', 'refunded', 'revoked')),
  purchased_at TEXT,
  granted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX purchase_grants_player_idx
  ON purchase_grants(player_id, granted_at DESC);

CREATE TABLE rematch_invitations (
  id TEXT PRIMARY KEY,
  previous_match_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  recipient_id TEXT NOT NULL,
  difficulty TEXT NOT NULL CHECK(difficulty IN ('beginner', 'easy', 'medium', 'hard', 'expert')),
  status TEXT NOT NULL CHECK(status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled', 'insufficient_coins')),
  room_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  responded_at TEXT,
  UNIQUE(previous_match_id, sender_id, recipient_id, created_at),
  FOREIGN KEY(previous_match_id) REFERENCES matches(id) ON DELETE CASCADE,
  FOREIGN KEY(sender_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(recipient_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX rematch_pending_recipient_idx
  ON rematch_invitations(recipient_id, status, expires_at);

-- The existing duel settlement code historically applies +100 to the winner and
-- -100 to the loser. For escrow-funded matches, intercept those two legacy
-- updates and replace them with one clean +200 payout recorded in the ledger.
CREATE TRIGGER escrow_prepare_winner_payout AFTER INSERT ON match_coin_settlements WHEN EXISTS ( SELECT 1 FROM match_coin_escrow WHERE match_id = NEW.match_id AND status = 'funded' ) BEGIN INSERT OR IGNORE INTO match_coin_intercepts ( match_id, winner_id, loser_id, created_at ) VALUES (NEW.match_id, NEW.winner_id, NEW.loser_id, NEW.applied_at); UPDATE players SET online_coins = online_coins + 200 WHERE id = NEW.winner_id; INSERT OR IGNORE INTO coin_ledger ( id, player_id, amount, balance_after, reason, reference_type, reference_id, idempotency_key, metadata_json, created_at ) VALUES ( lower(hex(randomblob(16))), NEW.winner_id, 200, (SELECT online_coins FROM players WHERE id = NEW.winner_id), 'match_payout', 'match', NEW.match_id, 'match_payout:' || NEW.match_id, json_object('pot', 200, 'entryFee', 100), NEW.applied_at ); UPDATE match_coin_escrow SET status = 'paid', winner_id = NEW.winner_id, settled_at = NEW.applied_at WHERE match_id = NEW.match_id AND status = 'funded'; END;

CREATE TRIGGER escrow_ignore_legacy_winner_update BEFORE UPDATE OF online_coins ON players WHEN NEW.online_coins = OLD.online_coins + 100 AND EXISTS ( SELECT 1 FROM match_coin_intercepts WHERE winner_id = OLD.id AND winner_update_pending = 1 ) BEGIN UPDATE match_coin_intercepts SET winner_update_pending = 0 WHERE winner_id = OLD.id AND winner_update_pending = 1; SELECT RAISE(IGNORE); END;

CREATE TRIGGER escrow_ignore_legacy_loser_update BEFORE UPDATE OF online_coins ON players WHEN NEW.online_coins = OLD.online_coins - 100 AND EXISTS ( SELECT 1 FROM match_coin_intercepts WHERE loser_id = OLD.id AND loser_update_pending = 1 ) BEGIN UPDATE match_coin_intercepts SET loser_update_pending = 0 WHERE loser_id = OLD.id AND loser_update_pending = 1; SELECT RAISE(IGNORE); END;

-- Draws and pre-start cancellations have no legacy coin settlement row, so
-- refund each funded entry when the match becomes terminal without a winner.
CREATE TRIGGER escrow_refund_draw_or_cancel AFTER UPDATE OF status ON matches WHEN NEW.status IN ('completed', 'cancelled', 'abandoned') AND NEW.winner_id IS NULL AND EXISTS ( SELECT 1 FROM match_coin_escrow WHERE match_id = NEW.id AND status = 'funded' ) BEGIN UPDATE players SET online_coins = online_coins + 100 WHERE id IN (NEW.player_a_id, NEW.player_b_id); INSERT OR IGNORE INTO coin_ledger ( id, player_id, amount, balance_after, reason, reference_type, reference_id, idempotency_key, metadata_json, created_at ) VALUES ( lower(hex(randomblob(16))), NEW.player_a_id, 100, (SELECT online_coins FROM players WHERE id = NEW.player_a_id), 'match_refund', 'match', NEW.id, 'match_refund:' || NEW.id || ':' || NEW.player_a_id, json_object('entryFee', 100), COALESCE(NEW.finished_at, NEW.updated_at) ); INSERT OR IGNORE INTO coin_ledger ( id, player_id, amount, balance_after, reason, reference_type, reference_id, idempotency_key, metadata_json, created_at ) VALUES ( lower(hex(randomblob(16))), NEW.player_b_id, 100, (SELECT online_coins FROM players WHERE id = NEW.player_b_id), 'match_refund', 'match', NEW.id, 'match_refund:' || NEW.id || ':' || NEW.player_b_id, json_object('entryFee', 100), COALESCE(NEW.finished_at, NEW.updated_at) ); UPDATE match_coin_escrow SET status = 'refunded', settled_at = COALESCE(NEW.finished_at, NEW.updated_at) WHERE match_id = NEW.id AND status = 'funded'; END;
