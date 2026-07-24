PRAGMA foreign_keys = ON;

CREATE TABLE players (
  id TEXT PRIMARY KEY,
  firebase_uid TEXT NOT NULL UNIQUE,
  public_id TEXT NOT NULL UNIQUE,
  username TEXT NOT NULL UNIQUE,
  username_normalized TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  avatar_key TEXT NOT NULL DEFAULT 'default',
  rating INTEGER NOT NULL DEFAULT 1000,
  games_played INTEGER NOT NULL DEFAULT 0,
  wins INTEGER NOT NULL DEFAULT 0,
  losses INTEGER NOT NULL DEFAULT 0,
  achievement_count INTEGER NOT NULL DEFAULT 0,
  google_player_id_hash TEXT,
  apple_player_id_hash TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE INDEX players_username_search_idx
  ON players(username_normalized);
CREATE INDEX players_rating_idx
  ON players(rating DESC);

CREATE TABLE device_tokens (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL CHECK(platform IN ('android', 'ios')),
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX device_tokens_player_idx
  ON device_tokens(player_id, enabled);

CREATE TABLE friendships (
  player_low_id TEXT NOT NULL,
  player_high_id TEXT NOT NULL,
  requester_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('pending', 'accepted', 'declined', 'blocked')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_low_id, player_high_id),
  FOREIGN KEY(player_low_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(player_high_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(requester_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX friendships_status_idx
  ON friendships(status, updated_at DESC);

CREATE TABLE challenges (
  id TEXT PRIMARY KEY,
  challenger_id TEXT NOT NULL,
  recipient_id TEXT NOT NULL,
  difficulty TEXT NOT NULL CHECK(difficulty IN ('beginner', 'easy', 'medium', 'hard', 'expert')),
  status TEXT NOT NULL CHECK(status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled', 'completed')),
  room_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  FOREIGN KEY(challenger_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(recipient_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX challenges_recipient_status_idx
  ON challenges(recipient_id, status, created_at DESC);
CREATE INDEX challenges_challenger_status_idx
  ON challenges(challenger_id, status, created_at DESC);

CREATE TABLE recent_opponents (
  player_low_id TEXT NOT NULL,
  player_high_id TEXT NOT NULL,
  last_challenge_id TEXT,
  last_winner_id TEXT,
  last_played_at TEXT NOT NULL,
  PRIMARY KEY(player_low_id, player_high_id),
  FOREIGN KEY(player_low_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(player_high_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(last_challenge_id) REFERENCES challenges(id) ON DELETE SET NULL,
  FOREIGN KEY(last_winner_id) REFERENCES players(id) ON DELETE SET NULL
);

CREATE INDEX recent_opponents_last_played_idx
  ON recent_opponents(last_played_at DESC);

CREATE TABLE request_limits (
  key TEXT PRIMARY KEY,
  window_started_at INTEGER NOT NULL,
  count INTEGER NOT NULL
);
