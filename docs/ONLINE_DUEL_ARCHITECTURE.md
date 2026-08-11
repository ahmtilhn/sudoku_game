# Online Duel Architecture

## Components

- Firebase Auth: every private REST and WebSocket request requires a Firebase ID
  token.
- Firebase App Check: Flutter sends `X-Firebase-AppCheck` when available.
  `REQUIRE_APP_CHECK` stays `false` until console metrics and staging tests pass.
- Cloudflare Worker: authenticates users, owns REST endpoints, creates match
  rows, and routes WebSocket upgrades.
- `GameRoom` Durable Object: authoritative live match state, turn validation,
  timers, reconnect grace, public snapshots, and settlement trigger.
- D1: persistent players, challenges, matches, ratings, leaderboards, audit, and
  idempotent settlement marker.
- Flutter client: renders state and sends requested actions only.

## Trust Boundaries

The mobile client is not trusted for score, winner, correctness, board state,
rating, or timing. The Durable Object owns solution and turn deadlines. D1
settlement uses DO state, not client claims.

## Current Implementation Boundary

This branch implements a server-authoritative vertical slice and local tests.
It has not been deployed to Cloudflare staging and has not completed the
two-token WebSocket smoke test. Therefore the production gate remains closed.

