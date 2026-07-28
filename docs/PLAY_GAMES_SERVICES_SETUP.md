# Play Games Services Setup

## Scope

Google Play Games Services is a platform mirror and optional social import source. Firebase UID remains the account owner. The backend must not trust a player ID sent directly by the client.

## Play Console checklist

1. Create or attach the Play Games Services project in Play Console.
2. Configure the game services project ID in Android resources and manifest metadata.
3. Configure OAuth consent and linked Android OAuth client.
4. Configure achievements and leaderboards.
5. Keep platform achievement mirroring limited to durable achievements.
6. Configure friends access only behind an explicit user action and consent flow.

## Client rules

- Use Play Games Services v2 frictionless authentication.
- Request a one-time server auth code for backend identity verification.
- Treat game-scoped player ID, display name, and avatar URL as platform metadata.
- Do not block offline Sudoku when Play Games auth fails.
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

## Leaderboards and achievements

- Submit leaderboard scores only after backend settlement is final.
- Failed platform submissions go to a retry queue.
- Platform leaderboards never settle ELO, Coins, tournament rewards, or country score.
- Mirror scopes:
  - `daily`: daily tournament.
  - `weekly`: weekend or weekly event.
  - `all_time`: backend-approved all-time board.

## Manual validation

- No platform account keeps the app playable.
- Server auth code replay is rejected.
- Client player ID mismatch is rejected.
- Friends consent denied imports nothing.
- Platform mirror failure does not roll back backend achievement unlocks.
