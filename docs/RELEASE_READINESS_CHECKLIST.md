# Release Readiness Checklist

Use this checklist after local validation passes. Do not commit secrets, service account JSON files, private keys, signing keys or certificate private keys.

## 1. Yerel kod doğrulama

- Where: repo root.
- Command: `flutter pub get`, `dart format lib test`, `git diff --check`, `flutter analyze`, `flutter test --reporter expanded --concurrency=1 --timeout 60s`, Worker `npm ci`, `npm run typecheck`, `npm test`.
- Verify: every command exits 0; no skipped tests.
- Misconfig symptom: analyzer/test failures, localization catalog test failures, or Worker TypeScript errors.

Production promotion must also pass the repository gate below. It refuses a
production config with App Check disabled and requires a live two-token ranked
WebSocket smoke test before deployment:

```powershell
$env:PLAYER_A_ID_TOKEN = '<token-a>'
$env:PLAYER_B_ID_TOKEN = '<token-b>'
powershell -ExecutionPolicy Bypass -File .\scripts\promote_production.ps1 `
	-BackendUrl "https://sudoku-duel-social-production.ilhanahmet246.workers.dev" `
	-BuildCommit (git rev-parse HEAD)
```

Never put token values in files, command history, CI logs, or issue comments.

## 2. Cloudflare D1 Migration

- Where: `backend/social_worker`.
- Staging command: `.\node_modules\.bin\wrangler.cmd d1 migrations apply sudoku-duel-social-staging --remote --config wrangler.staging.toml`.
- Production command: replace database/config with production names from `wrangler.toml`.
- Verify: Wrangler reports all migrations through `0015_account_deletion.sql` applied.
- Misconfig symptom: missing `DB` binding, wrong database id, or migration already modified after apply.

## 3. Cloudflare Worker Secrets

- Where: Cloudflare Worker dashboard or `wrangler secret put`.
- Names: `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`, `GOOGLE_PLAY_CLIENT_EMAIL`, `GOOGLE_PLAY_PRIVATE_KEY`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY`.
- Format: paste secret values only into Cloudflare; never write them into the repo.
- Verify: staging purchase, push and App Store/Play verification routes return configured errors or success, not missing-secret errors.
- Misconfig symptom: `production_verification_not_configured`, FCM send failures, 401/403 from store APIs.

## 4. Staging Deploy

- Where: `backend/social_worker`.
- Command: `.\node_modules\.bin\wrangler.cmd deploy --config wrangler.staging.toml`.
- Verify: Worker URL responds and Flutter build uses `--dart-define=SOCIAL_BACKEND_URL=<staging-url>`.
- Misconfig symptom: app shows backend unavailable or WebSocket connection fails.

## 5. Firebase Authentication

- Where: Firebase Console, project `focus-sweep-503417-d7`.
- Set: Anonymous and Email/Password providers enabled.
- Verify: guest sign-in, link email/password, sign-in, resend verification email and reset password on Android/iOS.
- Misconfig symptom: `ADMIN_ONLY_OPERATION`, provider disabled, verification links do not open.

## 6. Firebase App Check

- Where: Firebase Console and Worker vars.
- Var: `ALLOWED_APP_CHECK_APP_IDS` as comma-separated Firebase app IDs.
- Verify: debug/staging allows expected tokens; production `REQUIRE_APP_CHECK=true` rejects missing/invalid tokens.
- Misconfig symptom: `app_check_required`, `app_check_app_not_allowed`.

## 7. Firebase Cloud Messaging

- Where: Firebase Console and Cloudflare secrets.
- Vars: `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`.
- Verify: device token registration, push challenge, token delete on account deletion.
- Misconfig symptom: no notification delivery or Worker FCM auth errors.

## 8. APNs

- Where: Apple Developer and Firebase Cloud Messaging iOS settings.
- Format: APNs auth key/team/key id configured in Firebase.
- Verify: iOS physical device receives challenge/rematch push.
- Misconfig symptom: Android push works but iOS push never arrives.

## 9. Google Play Products

- Where: Play Console.
- Product IDs: `coins_100`, `coins_500`, `coins_1000`, `coins_5000`, `coins_10000`, `coins_50000`, `coins_100000`.
- Verify: products active and visible from an internal-testing install.
- Misconfig symptom: Coin Store product query returns empty.

## 10. Google Play Service Account

- Where: Google Cloud IAM and Play Console API access.
- Vars: `GOOGLE_PLAY_CLIENT_EMAIL`, `GOOGLE_PLAY_PRIVATE_KEY`, `GOOGLE_PLAY_PACKAGE_NAME=com.devoviastudio.sudoku`.
- Verify: valid purchase grants once, replay grants zero.
- Misconfig symptom: Google API 401/403 or package/product mismatch.

## 11. App Store Products

- Where: App Store Connect.
- Product IDs: same `coins_*` consumables as Google Play.
- Verify: StoreKit sandbox purchase appears and backend grants once.
- Misconfig symptom: product not found or transaction product mismatch.

## 12. App Store Connect API Key

- Where: App Store Connect Users and Access.
- Vars: `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY`, `APPLE_BUNDLE_ID=com.devoviastudio.sudoku`.
- Verify: sandbox and production transaction lookup both return signed data accepted by backend.
- Misconfig symptom: Apple API 401/404 or bundle/environment mismatch.

## 13. AdMob Application

- Where: AdMob.
- Needed values: Android App ID and iOS App ID.
- Format: `ca-app-pub-<publisher>~<app>`.
- Verify: replace test App IDs before release; run `scripts/check_release_readiness.ps1`.
- Misconfig symptom: readiness check fails on Google test App IDs.

## 14. AdMob Rewarded Units

- Where: AdMob ad units.
- Dart defines: `ADMOB_ANDROID_REWARDED_ID`, `ADMOB_IOS_REWARDED_ID`, `ADMOB_ANDROID_REWARDED_INTERSTITIAL_ID`, `ADMOB_IOS_REWARDED_INTERSTITIAL_ID`.
- Format: `ca-app-pub-<publisher>/<unit>`.
- Verify: physical device loads production units in a release candidate.
- Misconfig symptom: ads unavailable or test unit blocked in readiness review.

## 15. AdMob SSV

- Where: AdMob ad unit SSV settings and Worker vars.
- Callback URL: `https://<worker-host>/v1/rewards/admob/ssv`.
- Custom data: prepared reward token from the app.
- Worker var: `ADMOB_REWARDED_AD_UNITS` comma-separated real unit IDs.
- Verify: valid SSV marks reward verified; replay and wrong ad unit grant zero.
- Misconfig symptom: `reward_waiting_for_ssv`, `ssv_signature_invalid`, `ssv_ad_unit_not_allowed`.

## 16. Android Sandbox Test

- Where: Play internal testing on a physical Android device.
- Verify: account protection, purchase success/cancel/pending/replay, rewarded ad, push and online duel.

## 17. iOS Sandbox Test

- Where: TestFlight or development build on a physical iOS device.
- Verify: account protection, purchase success/cancel/replay, rewarded ad, APNs and online duel.

## 18. Android to Android Duel

- Verify: same difficulty matchmaking, 100 Coin debit each, winner +200 pot, forfeit payout, reconnect no second entry fee.

## 19. iOS to iOS Duel

- Verify: same as Android to Android, including APNs challenge/rematch.

## 20. Android to iOS Duel

- Verify: cross-platform matchmaking, challenge, rematch and settlement.

## 21. Purchase Replay Test

- Verify: same Google purchase token or Apple transaction ID cannot grant twice or to another player.

## 22. Rewarded Ad Replay Test

- Verify: same AdMob `transaction_id` and prepared token cannot grant twice, including parallel callback attempts.

## 23. Account Recovery Test

- Verify: guest links email, reinstalls/signs in, wallet/Friend ID/rating persist.

## 24. Account Deletion Test

- Verify: push token removed, active match policy enforced, server data deleted, Firebase user deleted, tombstone blocks UID recreation.

## 25. Privacy Policy

- Where: public HTTPS URL.
- Verify: covers Firebase UID/email, Friend ID, purchases, ads, push tokens, account deletion and tombstone retention.

## 26. Google Play Data Safety

- Where: Play Console.
- Verify: declarations match `docs/PRIVACY_AND_STORE_DISCLOSURES.md`.

## 27. Apple App Privacy

- Where: App Store Connect.
- Verify: declarations match actual SDKs, ATT/UMP behavior, purchases, identifiers and diagnostics.
