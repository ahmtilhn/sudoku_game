PRAGMA foreign_keys = ON;

CREATE TABLE matches (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL UNIQUE,
  challenge_id TEXT UNIQUE,
  mode TEXT NOT NULL CHECK(mode IN ('friendly', 'ranked')),
  difficulty TEXT NOT NULL CHECK(difficulty IN ('beginner', 'easy', 'medium', 'hard', 'expert')),
  status TEXT NOT NULL CHECK(status IN ('waiting', 'countdown', 'active', 'paused', 'completed', 'forfeited', 'cancelled', 'abandoned')),
  puzzle_fingerprint TEXT,
  player_a_id TEXT NOT NULL,
  player_b_id TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  winner_id TEXT,
  finish_reason TEXT,
  rated INTEGER NOT NULL DEFAULT 0,
  rating_settled_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(challenge_id) REFERENCES challenges(id) ON DELETE SET NULL,
  FOREIGN KEY(player_a_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(player_b_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(winner_id) REFERENCES players(id) ON DELETE SET NULL
);

CREATE INDEX matches_room_id_idx ON matches(room_id);
CREATE INDEX matches_status_updated_idx ON matches(status, updated_at DESC);
CREATE INDEX matches_finished_idx ON matches(finished_at DESC);
CREATE INDEX matches_player_a_idx ON matches(player_a_id, finished_at DESC);
CREATE INDEX matches_player_b_idx ON matches(player_b_id, finished_at DESC);

CREATE TABLE match_players (
  match_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  seat TEXT NOT NULL CHECK(seat IN ('A', 'B')),
  result TEXT CHECK(result IN ('win', 'loss', 'draw', 'cancelled')),
  score INTEGER NOT NULL DEFAULT 0,
  mistakes INTEGER NOT NULL DEFAULT 0,
  correct_moves INTEGER NOT NULL DEFAULT 0,
  timeouts INTEGER NOT NULL DEFAULT 0,
  rating_before_global INTEGER,
  rating_after_global INTEGER,
  rating_delta_global INTEGER,
  rating_before_difficulty INTEGER,
  rating_after_difficulty INTEGER,
  rating_delta_difficulty INTEGER,
  joined_at TEXT NOT NULL,
  disconnected_at TEXT,
  PRIMARY KEY(match_id, player_id),
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX match_players_player_idx ON match_players(player_id, joined_at DESC);
CREATE INDEX match_players_match_seat_idx ON match_players(match_id, seat);

CREATE TABLE player_ratings (
  player_id TEXT NOT NULL,
  scope TEXT NOT NULL CHECK(scope IN ('global', 'beginner', 'easy', 'medium', 'hard', 'expert')),
  rating INTEGER NOT NULL DEFAULT 1000,
  games_played INTEGER NOT NULL DEFAULT 0,
  wins INTEGER NOT NULL DEFAULT 0,
  losses INTEGER NOT NULL DEFAULT 0,
  draws INTEGER NOT NULL DEFAULT 0,
  win_streak INTEGER NOT NULL DEFAULT 0,
  best_rating INTEGER NOT NULL DEFAULT 1000,
  provisional_games INTEGER NOT NULL DEFAULT 20,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_id, scope),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX player_ratings_leaderboard_idx
  ON player_ratings(scope, rating DESC, games_played DESC, updated_at ASC);

CREATE TABLE match_audit (
  match_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  player_id TEXT,
  event_timestamp TEXT NOT NULL,
  payload_digest TEXT NOT NULL,
  PRIMARY KEY(match_id, sequence),
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE SET NULL
);

CREATE INDEX match_audit_type_idx ON match_audit(event_type, event_timestamp DESC);

CREATE TABLE ranked_queue (
  player_id TEXT PRIMARY KEY,
  difficulty TEXT NOT NULL CHECK(difficulty IN ('beginner', 'easy', 'medium', 'hard', 'expert')),
  rating INTEGER NOT NULL DEFAULT 1000,
  joined_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  room_id TEXT,
  matched_player_id TEXT,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX ranked_queue_difficulty_rating_idx
  ON ranked_queue(difficulty, rating, joined_at);

CREATE TABLE match_settlements (
  match_id TEXT PRIMARY KEY,
  settlement_hash TEXT NOT NULL,
  settled_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE
);

CREATE TABLE recent_ranked_pairs (
  player_low_id TEXT NOT NULL,
  player_high_id TEXT NOT NULL,
  utc_day TEXT NOT NULL,
  rated_count INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_low_id, player_high_id, utc_day),
  FOREIGN KEY(player_low_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(player_high_id) REFERENCES players(id) ON DELETE CASCADE
);
