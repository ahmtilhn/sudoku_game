# Online Duel Security Gap

Reviewed on 2026-07-26 from branch `agent-integrate-codex-firebase`.

## What Exists

- Firebase ID-token authentication for social API requests.
- Player profile creation and lookup.
- Friend request, friend response, recent opponent, and challenge endpoints.
- Device FCM token registration and opt-out disable route.
- Pending challenge creation, expiry, accept, and decline.
- Durable Object WebSocket room creation for accepted challenges.
- Room connection checks that require the authenticated player to be one of the challenge participants.
- WebSocket transport for `ready`, `move`, `forfeit`, and `ping` messages.

## What Is Missing for Ranked Production

- Server-side Sudoku puzzle generation.
- One shared authoritative puzzle seed per room.
- Server-side move validation.
- Server-owned board state.
- Per-player mistake state.
- Reconnect snapshots.
- Timeout handling.
- Forfeit settlement.
- Winner settlement.
- Rating updates.
- Match statistics.
- Recent opponent updates after completed matches.
- Anti-cheat checks.
- Replay and audit logs.

## Attack Scenarios

- A modified client can submit invalid moves.
- A modified client can claim a win without solving the board.
- A player can replay or reorder WebSocket messages.
- A client can hide mistakes locally.
- A reconnecting client can invent state if the server has no snapshot.
- A malicious client can attempt to force a forfeit or timeout state.

## Production Acceptance Criteria

- The server owns puzzle generation and solution validation.
- Clients receive only public puzzle state and submit candidate moves.
- The Durable Object stores room state and can return reconnect snapshots.
- Every result is derived from server state, not client claims.
- Rating/stat updates are idempotent and auditable.
- Timeouts and forfeits are settled server-side.
- Recent opponents and public stats are written only after validated settlement.

## Recommended Phases

1. Authoritative room state and shared puzzle seed.
2. Server-side move validation and reconnect snapshots.
3. Timeout and forfeit settlement.
4. Rating/stat/recent-opponent writes with idempotency.
5. Audit logs and abuse/rate-limit hardening.

Until these are complete, online duel results must not be treated as trusted ranked production outcomes.

