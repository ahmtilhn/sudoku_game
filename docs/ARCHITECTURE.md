# Architecture

## Current prototype

The first implementation is intentionally offline-first and keeps gameplay rules separate from presentation.

- `domain/`: Sudoku models, validation, candidate and completion rules.
- `data/`: validated puzzle catalog and local progress/settings persistence.
- `features/game/`: reusable solo game controller and screen.
- `features/duel/`: authoritative local turn loop used to validate future online rules.
- `widgets/`: reusable board and number controls.

## Online boundary

The future Cloudflare integration should not duplicate gameplay rules in Flutter. Flutter will send an intent such as `make_move`, and a Durable Object will return the authoritative board, score, turn number and `turnEndsAt` value.

Planned backend boundaries:

1. Firebase anonymous authentication creates a stable UID.
2. Cloudflare Worker validates the Firebase ID token.
3. Matchmaker Durable Object pairs two users.
4. One GameRoom Durable Object owns one match.
5. GameRoom validates cells, scores and 10-second timeouts.
6. Flutter renders server state and stores only personal history locally.

The local duel deliberately mirrors that state machine: one selected empty cell, one move per turn, +10 correct, -5 wrong and a timeout transition.
