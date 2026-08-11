# Architecture

## Current prototype

The first implementation is intentionally offline-first and keeps gameplay rules separate from presentation.

- `domain/`: Sudoku models, validation, candidate and completion rules.
- `data/`: unique random puzzle generation and local progress/settings/coin persistence.
- `features/game/`: reusable solo game controller, three-mistake career rule and recovery flow.
- `features/duel/`: difficulty selection, matchmaking queue model and authoritative local turn loop used to validate future online rules.
- `widgets/`: reusable board and number controls.

Career mode no longer uses a fixed level catalog. The player selects a difficulty and the client generates a fresh puzzle with one verified solution. Difficulty currently controls the target clue count. Career progress is stored per difficulty rather than per generated puzzle ID.

## Online boundary

The future Cloudflare integration must not duplicate or trust gameplay state from Flutter. Flutter sends an intent such as `join_queue` or `make_move`, and a Durable Object returns the authoritative board, score, turn number and `turnEndsAt` value.

Matchmaking queues are separated by difficulty:

- `duel_beginner`
- `duel_easy`
- `duel_medium`
- `duel_hard`
- `duel_expert`

Only players in the same queue can be paired. The client sends the selected difficulty, but the Matchmaker Durable Object decides the queue membership.

Planned backend boundaries:

1. Firebase anonymous authentication creates a stable UID.
2. Cloudflare Worker validates the Firebase ID token.
3. Matchmaker Durable Object places the user in the queue matching the selected difficulty.
4. Matchmaker pairs two users from the same difficulty queue.
5. One GameRoom Durable Object owns one match.
6. GameRoom generates or selects the unique puzzle and keeps the solution server-side.
7. GameRoom validates cells, scores and 10-second timeouts.
8. Flutter renders server state and stores only personal history locally.

The local duel mirrors that state machine: one selected empty cell, one move per turn, +10 correct, -5 wrong and a timeout transition. The local generator is used only for offline career, daily play and local practice; online clients must never be allowed to choose the puzzle or submit the solution.

## Career recovery boundary

Career mode ends the current attempt after three wrong moves. Recovery options are modeled as callbacks so monetization can be connected without coupling the game screen to an ad or billing SDK:

- spend the configured coin cost and continue the current board,
- finish a rewarded-ad flow and continue the current board,
- restart the generated puzzle from its initial state for free.

The prototype stores coins locally. Before release, coin spending and rewarded-ad grants that affect paid value must be validated by a trusted backend or store receipt flow.
