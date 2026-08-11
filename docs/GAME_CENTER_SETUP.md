# Game Center Setup

## Scope

Game Center is a platform mirror and identity proof provider. Firebase UID remains the account owner. The backend must not link a Game Center account until the Game Center identity signature is verified server-side.

## Console and Xcode checklist

1. Enable Game Center for the app identifier in Apple Developer.
2. Add the Game Center capability to the iOS target.
3. Confirm the bundle ID matches the Firebase iOS app and backend `IOS_BUNDLE_ID` config.
4. Configure achievements and recurring leaderboards in App Store Connect.
5. Keep the platform achievement set small. Mirror only durable, high-value internal achievements.
6. Add a platform dashboard access point in the app, but keep offline Sudoku available when authentication fails.

## Client rules

- Use `GKLocalPlayer` authentication as an optional platform session.
- Use `gamePlayerID`; do not use deprecated `playerID`.
- Use `displayName` only as a display suggestion.
- Load local player photo for local UI only.
- Do not upload Game Center photos to the backend automatically.
- Request identity verification items and send `publicKeyURL`, `signature`, `salt`, `timestamp`, `gamePlayerID`, and bundle ID to the backend.

## Backend verification

1. Verify Firebase ID token and App Check according to the endpoint policy.
2. Validate the bundle ID against backend config.
3. Reject stale timestamps.
4. Fetch the current Apple public key URL from the signed payload. Do not hardcode a certificate.
5. Verify the signature over the Game Center identity payload.
6. Hash the Game Center `gamePlayerID` before persistence.
7. Link the hash to the Firebase UID only after verification.
8. Treat account switches as a risk state that requires explicit user confirmation.

## Leaderboards and achievements

- Submit platform scores only after backend settlement is final.
- Platform leaderboard writes are mirror writes and never change backend ELO or tournament results.
- Use retry queue rows for failed mirror writes.
- Map backend scopes to platform boards explicitly:
  - `daily`: daily tournament mirror.
  - `weekly`: weekend or current-week event mirror.
  - `all_time`: stable global ELO or lifetime score mirror.

## Manual validation

- Device without Game Center account opens offline Sudoku.
- Game Center auth failure does not block the main menu.
- Invalid signature is rejected by backend.
- Expired signature is rejected by backend.
- Account switch does not overwrite the Firebase UID mapping silently.
