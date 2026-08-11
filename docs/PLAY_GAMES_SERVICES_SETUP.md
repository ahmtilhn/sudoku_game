# Play Games Services Setup

## Scope

Google Play Games Services and Game Center are platform mirrors and optional social import sources. Firebase UID remains the account owner. The backend must not trust a player ID or a rating sent directly by the client.

The Sudoku Duel backend is authoritative for current ELO, match settlement, Coins, friends, and match history. Platform leaderboards are display-only mirrors and never participate in settlement.

## Play Console checklist

1. Create or attach the Play Games Services project in Play Console.
2. Configure the game services project ID in Android resources and manifest metadata.
3. Configure OAuth consent and the linked Android OAuth client.
4. Configure achievements and leaderboards.
5. Keep platform achievement mirroring limited to durable achievements.
6. Configure friends access only behind an explicit user action and consent flow.

## Client rules

- Use Play Games Services v2 frictionless authentication.
- Request a one-time server auth code for backend identity verification.
- Treat game-scoped player ID, display name, and avatar URL as platform metadata.
- Do not block offline Sudoku when Play Games or Game Center authentication fails.
- Do not import platform friends until the user taps the import action and grants consent.

## Backend verification

1. Verify Firebase ID token and endpoint App Check policy.
2. Receive a one-time server auth code from the client.
3. Exchange the code server-side with Google OAuth using secrets stored outside source control.
4. Call Play Games Services APIs server-side to resolve the authenticated player.
5. Reject auth code replay by storing a hash of consumed codes.
6. Compare any client-provided player ID only as a consistency check.
7. Hash the verified game-scoped player ID before persistence.
8. Link the hash to Firebase UID only after server verification.

## Friends import

- Use our in-game friendship rows as the source of truth.
- Store platform-derived relations separately in `platform_friend_relations`.
- Re-verify imported platform relationships periodically.
- If consent is revoked or platform access disappears, mark the platform relation revoked without deleting the in-game friend relation.

## Current ELO versus platform peak ELO

The in-app leaderboards use the current server rating and can move both up and down. They expose these scopes:

- `global`
- `beginner`
- `easy`
- `medium`
- `hard`
- `expert`
- `friends`, which is a server-side filter rather than a separate platform leaderboard

Google Play Games ignores a submitted score when it is worse than the player's existing leaderboard score. Therefore the six public platform boards must be presented as **Highest ELO** or **Peak ELO**, not Current ELO. Configure Game Center with the same best-score behavior for cross-platform consistency.

Create exactly these six boards on both platforms:

| Order | Display name | Sort | Minimum | Maximum |
|---:|---|---|---:|---:|
| 1 | Highest Global ELO | Larger is better | 100 | 3000 |
| 2 | Highest Beginner ELO | Larger is better | 100 | 3000 |
| 3 | Highest Easy ELO | Larger is better | 100 | 3000 |
| 4 | Highest Medium ELO | Larger is better | 100 | 3000 |
| 5 | Highest Hard ELO | Larger is better | 100 | 3000 |
| 6 | Highest Expert ELO | Larger is better | 100 | 3000 |

Use numeric integer formatting with zero decimal places. Enable Play Games leaderboard tamper protection. Use a separate text-free 512 x 512 icon for each board.

## ID configuration

After creating the boards, replace the twelve placeholders in:

`lib/services/platform_leaderboard_service.dart`

Android placeholders:

- `REPLACE_WITH_PLAY_GAMES_GLOBAL_PEAK_ELO_ID`
- `REPLACE_WITH_PLAY_GAMES_BEGINNER_PEAK_ELO_ID`
- `REPLACE_WITH_PLAY_GAMES_EASY_PEAK_ELO_ID`
- `REPLACE_WITH_PLAY_GAMES_MEDIUM_PEAK_ELO_ID`
- `REPLACE_WITH_PLAY_GAMES_HARD_PEAK_ELO_ID`
- `REPLACE_WITH_PLAY_GAMES_EXPERT_PEAK_ELO_ID`

iOS placeholders:

- `REPLACE_WITH_GAME_CENTER_GLOBAL_PEAK_ELO_ID`
- `REPLACE_WITH_GAME_CENTER_BEGINNER_PEAK_ELO_ID`
- `REPLACE_WITH_GAME_CENTER_EASY_PEAK_ELO_ID`
- `REPLACE_WITH_GAME_CENTER_MEDIUM_PEAK_ELO_ID`
- `REPLACE_WITH_GAME_CENTER_HARD_PEAK_ELO_ID`
- `REPLACE_WITH_GAME_CENTER_EXPERT_PEAK_ELO_ID`

Until every required ID for the completed match is replaced, platform submission is skipped without affecting the match result or in-app ELO.

## Submission contract

- Submit only after a ranked match reaches final server settlement.
- Submit the local player's settled `afterGlobal` value to Highest Global ELO.
- Submit the settled `afterDifficulty` value to the matching difficulty board.
- Do not submit friendly matches, cancelled matches, client-calculated values, Coins, or raw Sudoku scores.
- A platform authentication or submission failure never rolls back backend settlement.
- The client deduplicates repeated final snapshots for the same match during the current process. Platform best-score behavior makes later duplicate submissions harmless.

## ELO contract

- Initial rating: `1000`.
- Supported range: `100..3000`.
- Result values: win `1.0`, draw `0.5`, loss `0.0`.
- K-factor: first 20 rated games `40`, games 21 through 100 `24`, after 100 games `16`.
- Global and played-difficulty rows are updated in the same settlement batch.
- Friendly matches and matches cancelled before start are not rated.
- Settlement is idempotent through `match_settlements` and `matches.rating_settled_at`.

## Manual validation

- No platform account keeps offline Sudoku playable.
- A ranked final snapshot submits exactly two values: global and played difficulty.
- Friendly and cancelled matches submit nothing.
- A duplicate final snapshot does not create another client submission in the same process.
- Rating can decrease in the app while the platform board continues to show the player's peak.
- Server auth code replay is rejected.
- Client player ID mismatch is rejected.
- Friends consent denied imports nothing.
- Platform mirror failure does not roll back backend rating or achievement unlocks.
