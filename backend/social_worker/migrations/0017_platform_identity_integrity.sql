PRAGMA foreign_keys = ON;

CREATE TABLE platform_identity_links (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('game_center', 'google_play_games')),
  platform_player_id_hash TEXT NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  verification_method TEXT NOT NULL,
  verified_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  revoked_at TEXT,
  metadata_json TEXT,
  UNIQUE(player_id, platform),
  UNIQUE(platform, platform_player_id_hash),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX platform_identity_links_player_idx
  ON platform_identity_links(player_id, platform, revoked_at);

CREATE TABLE platform_identity_challenges (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('game_center', 'google_play_games', 'ios_app_attest')),
  challenge_hash TEXT NOT NULL,
  request_hash TEXT,
  status TEXT NOT NULL DEFAULT 'issued'
    CHECK(status IN ('issued', 'consumed', 'expired', 'rejected')),
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL,
  metadata_json TEXT,
  UNIQUE(platform, challenge_hash),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX platform_identity_challenges_due_idx
  ON platform_identity_challenges(status, expires_at);

CREATE TABLE high_value_attestations (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('android', 'ios')),
  request_type TEXT NOT NULL CHECK(request_type IN (
    'tournament_start',
    'tournament_submit',
    'purchase_verification',
    'rewarded_reward'
  )),
  request_hash TEXT NOT NULL,
  token_hash TEXT NOT NULL,
  verdict TEXT NOT NULL DEFAULT 'pending'
    CHECK(verdict IN ('pending', 'passed', 'failed', 'unsupported', 'manual_review')),
  risk_state TEXT NOT NULL DEFAULT 'monitor'
    CHECK(risk_state IN ('monitor', 'allow', 'limited', 'manual_review', 'block')),
  app_check_present INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  expires_at TEXT,
  used_at TEXT,
  metadata_json TEXT,
  UNIQUE(token_hash),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX high_value_attestations_player_idx
  ON high_value_attestations(player_id, request_type, created_at DESC);

CREATE TABLE platform_friend_relations (
  player_id TEXT NOT NULL,
  friend_player_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('game_center', 'google_play_games')),
  platform_relation_hash TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'imported'
    CHECK(status IN ('imported', 'verified', 'revoked')),
  consent_version TEXT NOT NULL,
  last_verified_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(player_id, friend_player_id, platform),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE,
  FOREIGN KEY(friend_player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX platform_friend_relations_verify_idx
  ON platform_friend_relations(platform, status, last_verified_at);

CREATE TABLE platform_leaderboard_mirror_queue (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK(platform IN ('game_center', 'google_play_games')),
  leaderboard_key TEXT NOT NULL,
  scope TEXT NOT NULL CHECK(scope IN ('daily', 'weekly', 'all_time')),
  score INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending', 'synced', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(player_id, platform, leaderboard_key, scope),
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX platform_leaderboard_mirror_due_idx
  ON platform_leaderboard_mirror_queue(status, next_attempt_at);
