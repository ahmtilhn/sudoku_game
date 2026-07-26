# Online Duel Completion Report

## Summary

- Start branch: `agent-integrate-codex-firebase`
- Start commit: `ff7980b17c8cb10092732ac1e5113ff01ec0ad61`
- Work branch: `codex-authoritative-online-duel`
- End commit: this report's PR head commit
- Base PR: #21, not merged during this work
- Decision: `NOT READY FOR TWO-DEVICE STAGING TEST`

The branch adds a server-authoritative online duel vertical slice, but it has
not passed a deployed two-socket/two-device staging test with real Firebase ID
tokens. Production-ready is also false until Cloudflare deployment, App Check
verification, abuse testing, policy updates, and physical-device validation are
complete.

## Changed Areas

- D1 migration `0002_authoritative_online_duel.sql`
- `GameRoom` Durable Object authoritative state
- Ranked queue, ratings, match history, leaderboards REST endpoints
- Flutter online duel transport, controller, screen, and leaderboards screen
- Localization across Dart, Android, and iOS catalog
- Backend and Flutter automated tests
- Cloudflare example config and documentation

## Backend Endpoints

- `POST /v1/matchmaking/queue`
- `DELETE /v1/matchmaking/queue`
- `GET /v1/matches/active`
- `GET /v1/matches/history`
- `GET /v1/matches/:matchId`
- `GET /v1/me/ratings`
- `GET /v1/leaderboards/global`
- `GET /v1/leaderboards/:difficulty`
- existing `/v1/rooms/:roomId/connect` now serves authoritative rooms

## WebSocket Messages

Client messages: `ready`, `move`, `forfeit`, `request_snapshot`, `ping`.

Server events: `connected`, `snapshot`, `player_presence`, `player_ready`,
`match_started`, `move_accepted`, `move_rejected`, `turn_changed`,
`turn_timeout`, `player_forfeited`, `match_completed`, `rating_updated`,
`pong`, `protocol_error`, `server_error`.

## Puzzle System

Ranked puzzle generation is backend-only and the solution remains inside the
Durable Object state. The Flutter model has no solution field. The current
puzzle generator is deterministic from server randomness and clue count; a
larger curated static puzzle bank with offline uniqueness-generation reporting
is still recommended before production.

## Timer and Reconnect

The server owns turn deadlines, ready deadline, disconnect grace, and DO alarms.
Client UI displays server snapshots only. Disconnect grace is bounded per seat.

## Settlement and Elo

Settlement is server-triggered for completed, forfeited, or cancelled matches.
Ranked matches update global and difficulty rating scopes with Elo. Friendly
matches do not change rating. Settlement has an idempotency marker, but remote
retry/failure-mode testing is still required before production.

## Flutter UI

- Ranked queue from `MatchmakingScreen`
- Online room screen with ready, server board, turn gating, forfeit confirm, and
  result panel
- Challenge accept opens `OnlineDuelScreen`
- Leaderboards screen with Global and difficulty tabs
- App Check token header is sent when available

## Validation Results

- `npm install`: passed, 0 vulnerabilities
- `npm run typecheck`: passed
- `npm test`: passed, 7 backend tests
- `npm run db:local`: passed with `wrangler.example.toml`
- `dart format lib test`: passed
- `python tool/validate_localizations.py`: passed, 139 keys
- `flutter analyze`: passed
- `flutter test --concurrency=1 --timeout 90s -r expanded`: passed, 22 tests
- `flutter build apk --debug`: passed
- `flutter build appbundle --release`: passed

## AAB

- Path: `build/app/outputs/bundle/release/app-release.aab`
- Size: `69267568`
- File SHA-256: `D19C0880A14E41DB84AFA9808D5BD4C9F2C6C8BFABA835E2C44E9E693015979D`
- Signing SHA-1: `D4:EA:36:D4:6C:F9:58:07:45:6B:A3:6D:28:1D:6A:DC:6D:2C:E9:48`
- Signing SHA-256: `4D:F5:C2:09:68:EE:BD:F9:A2:09:EA:B5:D9:D4:34:40:46:59:AE:81:35:C2:A4:87:85:97:49:EB:F7:66:ED:81`
- Version: `0.1.0+4`

## Security Review

- No service account JSON, keystore, `.dev.vars`, FCM private key, OAuth secret,
  or APNs key was added.
- Public snapshots exclude solution and private identifiers.
- Offline/local Sudoku remains independent from online services.
- App Check enforcement remains disabled by default.

## Unresolved Issues

- No deployed Cloudflare staging validation.
- No real two Firebase ID token WebSocket smoke test.
- App Check backend verification is not production-proven.
- Puzzle bank should be expanded into a curated verified data set before launch.
- Settlement retry needs remote failure-mode validation.

