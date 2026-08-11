PRAGMA foreign_keys = ON;

ALTER TABLE players ADD COLUMN online_coins INTEGER NOT NULL DEFAULT 0;

CREATE TABLE match_coin_settlements (
  match_id TEXT PRIMARY KEY,
  winner_id TEXT NOT NULL,
  loser_id TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK(amount = 100),
  applied_at TEXT NOT NULL,
  winner_balance_after INTEGER,
  loser_balance_after INTEGER,
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE,
  FOREIGN KEY(winner_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(loser_id) REFERENCES players(id) ON DELETE CASCADE
);
