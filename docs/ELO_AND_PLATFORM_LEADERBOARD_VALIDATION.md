# ELO and Platform Leaderboard Validation

## Decision

- The Sudoku Duel backend remains authoritative for current ELO.
- Google Play Games and Game Center receive display-only peak ELO submissions after final ranked settlement.
- Platform failure cannot change the match winner, current backend rating, Coins, or history.

## Current ELO implementation review

The ranked formula in `backend/social_worker/src/online_duel.ts` is:

```text
expected = 1 / (1 + 10 ^ ((opponent - player) / 400))
delta = round(K * (result - expected))
```

Result values:

- win: `1.0`
- draw: `0.5`
- loss: `0.0`

K-factor boundaries:

- completed rated games `0..19`: `40`
- completed rated games `20..99`: `24`
- completed rated games `100+`: `16`

The rating after settlement is clamped to `100..3000`.

## Settlement review

`GameRoom.settleIfNeeded` performs these operations:

1. Checks `match_settlements` before applying a result.
2. Loads both players' global and played-difficulty rows.
3. Calculates the two global changes and two difficulty changes from the pre-match values.
4. Writes match completion, match-player history, global ratings, difficulty ratings, player aggregates, challenge state, and Coin settlement in one D1 batch.
5. Marks the Durable Object state as settled and broadcasts the final server rating snapshot.

The existing `settlement_model.test.ts` covers retries at every settlement stage and verifies that repeated settlement calls produce one global update, one difficulty update, one history result, and one aggregate result.

## Added automated coverage

`backend/social_worker/test/elo_rating.test.ts` verifies:

- equal-rating win, draw, and loss values;
- exact K-factor transitions at games 20 and 100;
- favorite and underdog behavior;
- two-player symmetry when both players use the same K-factor;
- valid player-specific K-factor behavior;
- the `100..3000` clamp;
- finite and bounded results across representative rating gaps.

`test/platform_leaderboard_service_test.dart` verifies:

- exactly two platform submissions per settled ranked match;
- global and played-difficulty ID selection;
- local-seat rating selection;
- friendly and cancelled matches are ignored;
- placeholders disable submission safely;
- duplicate final snapshots are ignored in the same process;
- failed submissions can retry.

`test/online_duel_leaderboard_mirror_test.dart` verifies that `OnlineDuelController` forwards a settled server snapshot to the platform mirror.

## Why platform boards are Peak ELO

The in-app server leaderboard can display current ELO because the backend can replace a rating with either a higher or lower value.

Google Play Games keeps the better leaderboard score and ignores a worse submission. Therefore a Google leaderboard cannot accurately mirror a rating that decreases. The six platform boards are deliberately named Highest or Peak ELO. Game Center should use Best Score submission behavior to match Android.

The app still submits each final server rating. The platform decides whether it improves the player's stored peak.

## Platform board set

1. Highest Global ELO
2. Highest Beginner ELO
3. Highest Easy ELO
4. Highest Medium ELO
5. Highest Hard ELO
6. Highest Expert ELO

All six use:

- larger is better;
- integer numeric format;
- minimum `100`;
- maximum `3000`.

## Validation commands

Run from the repository root:

```powershell
flutter pub get
flutter analyze
flutter test --concurrency=1 --timeout 60s -r expanded

cd backend/social_worker
npm ci
npm run typecheck
npm test
```

Then perform physical-device validation:

1. Replace all platform leaderboard ID placeholders.
2. Authenticate with Play Games or Game Center.
3. Complete a ranked match.
4. Confirm that global and played-difficulty peak ELO are submitted.
5. Lose a later match and confirm the in-app current ELO decreases while the platform peak remains unchanged.
6. Reconnect to the completed match and confirm there is no harmful duplicate effect.
7. Complete a friendly match and confirm no platform score submission occurs.

## Release gate

The implementation is committed for validation. Production remains blocked until the full Flutter and Worker suites pass and both Android internal testing and iOS sandbox/TestFlight tests confirm real leaderboard IDs and authentication behavior.
