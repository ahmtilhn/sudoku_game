# Google Play Console Release Tasks

This is the execution checklist for the Google Play Console work that remains
after repository-side validation passes. Do not paste keystore passwords,
service-account private keys, OAuth client secrets, or tester account passwords
into this repository.

## App dashboard

1. Confirm package name is `com.devoviastudio.sudoku`.
2. Confirm the Play app is linked to Firebase project `focus-sweep-503417-d7`.
3. Confirm Play App Signing is enabled.
4. Copy the Play App Signing SHA-1 and SHA-256 fingerprints.
5. Add those fingerprints to the Firebase Android app.
6. Keep the upload-key SHA fingerprints documented locally outside the repo.

## Store listing

1. App name: `Sudoku Duel`.
2. Short description: mention Sudoku puzzles, career progress, and online duel.
3. Full description: include offline Sudoku, ranked online duel, optional
   rewarded ads, coins with no cash value, account deletion, and privacy
   controls.
4. Upload final app icon, feature graphic, phone screenshots, and tablet
   screenshots.
5. Set category to Games / Puzzle.
6. Add public support email and public privacy-policy URL.
7. Confirm the privacy-policy page opens without authentication.

## App content and policy

1. Complete Data Safety from `docs/PRIVACY_AND_STORE_DISCLOSURES.md`.
2. Declare account creation and in-app account deletion.
3. Declare optional push notifications for online challenges.
4. Declare ads and rewarded ads.
5. Declare purchases and transaction identifiers.
6. Complete target audience and content rating.
7. Add review notes for tester account flow if Play review needs it.

## Monetization products

Create active one-time consumable products with these exact product IDs:

| Product ID | Coins |
|---|---:|
| `coins_100` | 100 |
| `coins_500` | 500 |
| `coins_1000` | 1,000 |
| `coins_5000` | 5,000 |
| `coins_10000` | 10,000 |
| `coins_50000` | 50,000 |
| `coins_100000` | 100,000 |

For each product:

1. Add localized title and description.
2. State that Coins have no cash value and cannot be transferred.
3. Set price.
4. Activate the product.
5. Verify it appears from an internal-testing install.

## Play Games Services

1. Open Grow users > Play Games Services.
2. Link the game to the Google Cloud project used by Firebase.
3. Configure Android OAuth credentials for:
   - Play App Signing certificate SHA-1;
   - upload/release certificate SHA-1;
   - debug certificate SHA-1 only for local tests.
4. Configure the game-server web OAuth client.
5. Confirm the Android web client ID matches
   `android/app/src/main/res/values/services.xml`.
6. Create a global rating leaderboard.
7. Create a first online win achievement.
8. Replace these placeholders after creation:
   - `leaderboard_global_rating`;
   - `achievement_first_win`.
9. Publish the Play Games Services configuration to testers.
10. Test native sign-in, leaderboard, achievement unlock, and server auth code
    from a Play internal-testing install.

## Internal testing

1. Build a signed release AAB only after `scripts/check_release_readiness.ps1`
   passes.
2. Upload the AAB to Internal testing.
3. Add tester group.
4. Install only from the Play internal-testing link.
5. Verify cold start after uninstall/reinstall.
6. Verify online duel matchmaking, reconnect, forfeit, result, and wallet
   settlement on two devices.
7. Verify successful, cancelled, pending, and replayed purchases.
8. Verify rewarded ad success, no-fill/skip, and replay safety.
9. Check Android Vitals and Crashlytics before promoting.

## Values to copy back into the repo

After console setup is complete, update these files with non-secret IDs only:

- `android/app/src/main/res/values/services.xml`
  - `admob_app_id`
  - `facebook_app_id`, only if Meta remains enabled
  - `facebook_client_token`, only if Meta remains enabled
  - `leaderboard_global_rating`
  - `achievement_first_win`
- `ios/Flutter/Release.xcconfig`
  - `INFOPLIST_KEY_SudokuLeaderboardGlobalRating`
  - `INFOPLIST_KEY_SudokuAchievementFirstWin`
- `ios/Runner/Info.plist`
  - `GADApplicationIdentifier`
  - Meta keys only if Meta remains enabled

Do not copy service-account JSON, OAuth client secrets, keystore files, or
private keys into the repo.
