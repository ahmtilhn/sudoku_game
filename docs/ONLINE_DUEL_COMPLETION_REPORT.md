# Online Duel Completion Report

## Summary

- Start branch: `agent-integrate-codex-firebase`
- Start commit: `ff7980b17c8cb10092732ac1e5113ff01ec0ad61`
- Work branch: `codex-authoritative-online-duel`
- End commit: this report's PR head commit
- Base PR: #21, not merged during this work
- Decision: `READY FOR TWO-DEVICE STAGING TEST`

The branch now has the code-side gates needed to start a two-device staging
test: full smoke scripts, local/mock two-client protocol tests, App Check
verifier tests, verified backend-only puzzle bank, settlement retry tests,
Flutter transport tests, staging build tooling, and passing typecheck/analyze
test commands. This does not mean Cloudflare staging was deployed or production
is ready.

## Changed Areas

- D1 migration `0002_authoritative_online_duel.sql`
- `GameRoom` Durable Object authoritative state
- Ranked queue, ratings, match history, leaderboards REST endpoints
- Flutter online duel transport, controller, screen, and leaderboards screen
- Localization across Dart, Android, and iOS catalog
- Backend and Flutter automated tests
- Cloudflare example config and documentation
- Production-grade App Check verifier and staging preflight tools
- Backend-only ranked puzzle bank: 100 verified puzzles

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

Ranked puzzle selection is backend-only from `src/ranked_puzzles/*.json`.
There are 20 verified puzzles for each difficulty, 100 total. The solution
remains inside the Worker bundle and Durable Object state. Public snapshots and
Flutter models do not include solution.

## Timer and Reconnect

The server owns turn deadlines, ready deadline, disconnect grace, and DO alarms.
Client UI displays server snapshots only. Disconnect grace is bounded per seat.

## Settlement and Elo

Settlement is server-triggered for completed, forfeited, or cancelled matches.
Ranked matches update global and difficulty rating scopes with Elo. Friendly
matches do not change rating. The DO now checks `match_settlements` before
applying changes, and local failure-mode tests cover retry after each modeled
settlement step. Remote failure-mode testing is still required before
production.

## Flutter UI

- Ranked queue from `MatchmakingScreen`
- Online room screen with ready, server board, turn gating, forfeit confirm, and
  result panel
- Challenge accept opens `OnlineDuelScreen`
- Leaderboards screen with Global and difficulty tabs
- App Check token header is sent when available
- Header unit tests verify Firebase Auth and App Check tokens are not mixed

## Validation Results

- `npm install`: passed, 0 vulnerabilities
- `npm run typecheck`: passed
- `npm test`: passed, 31 backend tests
- `npm run puzzles:verify`: passed, 100 puzzles
- `npm run db:local`: passed with `wrangler.example.toml`
- `dart format --set-exit-if-changed lib test`: passed
- `python tool/validate_localizations.py`: passed, 139 keys
- `python tool/validate_translation_quality.py`: passed, 22 online keys
- `flutter analyze`: passed
- `flutter test --concurrency=1 --timeout 120s -r expanded`: passed, 24 tests
- `flutter build apk --debug`: passed
- `powershell -ExecutionPolicy Bypass -File ./tool/build_online_staging.ps1 -BackendUrl "https://example.invalid"`: passed as script validation build only

## AAB

- Path: `build/app/outputs/bundle/release/app-release.aab`
- Size: `69267934`
- File SHA-256: `DB511A9D8D824EC87DEAF903AF5FE36DC627673F77FFD99CE091E565EF4A445C`
- Signing SHA-1: `D4:EA:36:D4:6C:F9:58:07:45:6B:A3:6D:28:1D:6A:DC:6D:2C:E9:48`
- Signing SHA-256: `4D:F5:C2:09:68:EE:BD:F9:A2:09:EA:B5:D9:D4:34:40:46:59:AE:81:35:C2:A4:87:85:97:49:EB:F7:66:ED:81`
- Version: `0.1.0+4`

## Security Review

- No service account JSON, keystore, `.dev.vars`, FCM private key, OAuth secret,
  or APNs key was added.
- Public snapshots exclude solution and private identifiers.
- Offline/local Sudoku remains independent from online services.
- App Check enforcement remains disabled by default until staging metrics pass.
- App Check verifier validates RS256, issuer, audience, expiry, and allowed app IDs.

## Unresolved Issues

- No deployed Cloudflare staging validation was performed.
- Real `npm run smoke:two-player` and `npm run smoke:ranked` were not executed because staging URL and real Firebase/App Check tokens were not provided.
- Production-ready remains blocked by Cloudflare deployment, remote D1 migration, physical-device testing, App Check metrics/enforcement, abuse tests, monitoring, and policy updates.

