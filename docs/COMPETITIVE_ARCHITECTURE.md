# Competitive Architecture

This document locks the competitive boundaries before seasons, tournaments and country competition are implemented. Phase 0 is an audit and design phase only; it does not add tournament runtime behavior.

## Current Capability Matrix

| Area | Status | Evidence | Boundary |
|---|---|---|---|
| Ranked matchmaking | Present | `ranked_queue`, `/v1/matchmaking/queue`, difficulty/rating queue selection | Matchmaking chooses same difficulty and nearest rating; no season partition yet. |
| Rating settlement | Present | `player_ratings`, `match_players.rating_*`, `GameRoom.settleIfNeeded` | Server computes Elo deltas; client score/rating values are display-only. |
| Rating history | Partial | `match_players` stores per-match before/after values | No standalone immutable `rating_history` table. Add one in a later migration before seasons. |
| Seasons | Missing | No `seasons` table or current-season API | Do not overload existing `player_ratings`; add season-scoped tables. |
| Player avatar source | Partial | `players.avatar_key`, Flutter `avatarKey` | Only preset-style key exists. Source/version/synced URL are not modeled yet. |
| Platform identity mapping | Partial | `players.google_player_id_hash`, `players.apple_player_id_hash`, platform channel methods | Existing columns are hash placeholders; no verified binding lifecycle/API is implemented. |
| Friends | Present | `friendships`, friend request/respond routes | Backend friend graph is independent from platform friends. |
| Leaderboard | Present | `/v1/leaderboards/:scope`, `player_ratings_leaderboard_idx` | Supports `global` and difficulty scopes; no seasonal/country leaderboard. |
| Achievement rewards | Present | `/v1/achievements/:id/claim`, `reward_claims`, migration `0010` auto grant triggers | Rewards are server-side/idempotent; no tournament achievements yet. |
| Daily reward | Present | `daily_login`, daily rewarded ad reward claims | UTC-day reward keys; no season/event reward calendar. |
| Tournament tables | Missing | No tournament tables in migrations `0001`-`0015` | Add in later migrations only. |
| Scheduled Worker handler | Missing for top-level cron | `GameRoom.alarm()` exists, no exported `scheduled()` handler | Durable Object alarms manage duel deadlines; cron/event jobs need explicit scheduled export later. |
| Admin/event configuration | Missing | No admin config table/API | Future event configuration must be database-backed and access-controlled. |
| Anti-cheat/App Check enforcement | Partial | `verifyAppCheckRequest`, `REQUIRE_APP_CHECK` | App Check exists; production enforcement and integrity policy remain external-console gates. |

## Server Authority Rules

- The Worker owns Coin balances, ledger rows, escrow, refunds, store grants, ad grants and achievement rewards.
- The Worker owns online duel score, winner, finish reason, rating deltas and match settlement.
- The Flutter client may request actions and display snapshots only. It must not send authoritative score, Coin, rating, country score, achievement state, reward amount or tournament result values.
- Durable Object snapshots are transport and recovery state, not a long-term replay archive.
- `match_audit` may retain bounded security/audit digests. Do not add replay UI or long-term full move replay storage in this phase.

## Existing Competitive Data Ownership

| Data | Owner | Current storage | Notes |
|---|---|---|---|
| Account identity | Firebase Auth + Worker player row | `players.firebase_uid` | Firebase UID is the primary account key. |
| Public identity | Worker | `players.public_id`, `username`, `display_name` | `public_id` is permanent Friend ID; username is unique editable game name. |
| Rating | Worker | `player_ratings`, `match_players` | Per-scope rating is server-settled. |
| Wallet | Worker | `players.online_coins`, `coin_ledger`, `match_coin_escrow` | Ledger and idempotency keys are required for every mutation. |
| Match result | Worker Durable Object + D1 | `matches`, `match_players`, `match_settlements` | Client result payloads are not trusted. |
| Friends/challenges | Worker | `friendships`, `challenges`, `rematch_invitations` | Platform friends are only a discovery/input surface. |
| Push tokens | Worker + Firebase Messaging | `device_tokens` | Tokens are device-scoped and removed during account deletion. |

## Locked Feature Flags

All future competitive features must be gated server-side and mirrored in client config only for UI availability:

| Flag | Default | Purpose |
|---|---:|---|
| `premiumOnlineUi` | off | Enables enhanced competitive screens without changing settlement logic. |
| `rankedSeasons` | off | Enables season-scoped rating summaries and season leaderboards. |
| `globalTournaments` | off | Enables global tournament list, registration and attempts. |
| `countryTournaments` | off | Enables country team scoring and country leaderboards. |
| `platformAvatars` | off | Allows display of local platform avatar hints. |
| `syncedPlatformAvatars` | off | Allows explicit, consented avatar sync to backend storage. |
| `clans` | off | Reserved; no clan feature in current scope. |
| `integrityEnforcement` | off | Enables stricter App Check/device-integrity gates after console validation. |

## Draft API Contract

These endpoints are design contracts for later phases. They must reject unconfigured feature flags with a stable error code.

| Endpoint | Method | Server-owned result |
|---|---|---|
| `/v1/competitive/profile` | GET | Competitive identity, avatar metadata, flags and integrity status. |
| `/v1/ranked/summary` | GET | Global/difficulty rating summary, season status when enabled. |
| `/v1/seasons/current` | GET | Current season metadata and eligibility gates. |
| `/v1/tournaments` | GET | Visible tournaments filtered by feature flag, eligibility and status. |
| `/v1/tournaments/:id` | GET | Tournament details, registration status and server clock. |
| `/v1/tournaments/:id/register` | POST | Server-side registration/reservation, no client fee values. |
| `/v1/tournaments/:id/start-attempt` | POST | Server-reserved attempt and puzzle assignment. |
| `/v1/tournaments/:id/submit` | POST | Server validation result; client score is advisory at most. |
| `/v1/tournaments/:id/leaderboard` | GET | Server-ranked tournament results. |
| `/v1/tournaments/:id/countries` | GET | Server-computed country standings. |
| `/v1/countries/profile` | GET/PUT | Country selection/lock state and eligibility. |

## Migration Plan

Do not edit applied migrations `0001`-`0015`.

1. `0016_competitive_feature_flags.sql`: feature flag/config table with audit timestamps.
2. `0017_player_identity_avatar_sources.sql`: avatar source/version/synced URL/consent fields and platform identity binding records.
3. `0018_ranked_seasons.sql`: seasons, season rating snapshots and immutable rating history.
4. `0019_tournaments_core.sql`: tournaments, registration and attempt reservations.
5. `0020_tournament_results_and_country_scores.sql`: validated submissions, country profile locks and country aggregate tables.

## Phase 0 Decision

The current release candidate remains online-duel focused. Seasons, tournaments, country scoring, clan features and replay UI are explicitly out of scope until the migration plan above is implemented behind feature flags.
