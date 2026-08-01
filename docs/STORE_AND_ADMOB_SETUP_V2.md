# Store and AdMob Setup V2

## Coin products

Create the same consumable product IDs in Google Play Console and App Store Connect:

| Product ID | Granted Coins | Type |
|---|---:|---|
| `coins_100` | 100 | Consumable |
| `coins_500` | 500 | Consumable |
| `coins_1000` | 1,000 | Consumable |
| `coins_5000` | 5,000 | Consumable |
| `coins_10000` | 10,000 | Consumable |
| `coins_50000` | 50,000 | Consumable |
| `coins_100000` | 100,000 | Consumable |

The Flutter UI reads localized title, description, currency and price from the storefront. Do not hardcode real-money prices in the app.

## Android test path

1. Create one-time consumable products with the exact IDs above.
2. Activate the products and add license-test accounts.
3. Upload a signed internal-testing App Bundle using `com.devoviastudio.sudoku`.
4. Install from the Play internal-testing link; sideloaded builds do not exercise the complete Play Billing sandbox path.
5. Verify pending, successful, cancelled and repeated consumable purchases.
6. Give the Worker service account access to the app in Play Console and enable the Google Play Android Developer API.
7. Set Worker secrets `GOOGLE_PLAY_CLIENT_EMAIL` and `GOOGLE_PLAY_PRIVATE_KEY`.
8. Set `GOOGLE_PLAY_PACKAGE_NAME = "com.devoviastudio.sudoku"`.

Production verification uses the ProductPurchaseV2 API, checks the purchase is `PURCHASED`, checks the product ID, grants once, and consumes the product after the backend grant succeeds. Consumption failure is recorded and must be monitored/retried; it never causes a second Coin grant.

## iOS test path

1. Create consumable In-App Purchases with the exact IDs above.
2. Complete localization, pricing and review metadata for every product.
3. Create StoreKit sandbox testers.
4. Test from a development/TestFlight build signed with `com.devoviastudio.sudoku`.
5. Verify successful, cancelled, interrupted and repeated consumable purchases.
6. Create an App Store Connect In-App Purchase key.
7. Set Worker secrets `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, and `APPLE_IAP_PRIVATE_KEY`.
8. Set `APPLE_BUNDLE_ID = "com.devoviastudio.sudoku"`.

Production verification calls App Store Server API Get Transaction Info, checks transaction ID, product ID, bundle ID, ownership, product type and revocation state, and then grants once. The Worker tries production first and sandbox for test transactions.

Current release blocker: the Worker decodes Apple `signedTransactionInfo` returned by the App Store Server API, but does not independently validate the JWS signature, Apple certificate chain, or Apple root trust. Keep iOS purchase verification blocked for production until an official Apple verifier compatible with the runtime is integrated, or move Apple verification behind a trusted server component that performs those checks.

## Purchase safety behavior

- Staging plus `ALLOW_TEST_PURCHASE_GRANTS=true` permits sandbox-flow integration while store credentials are being configured.
- Production routes use real Google Play/App Store server verification.
- Missing or rejected production credentials return an error and grant zero Coins.
- Transaction IDs and verification hashes are unique in D1 to prevent replay.
- A transaction previously used by another player is rejected.
- The client completes a store purchase only after the backend grant succeeds.
- Purchase grants, source, environment, order/original transaction ID and Android consumption state are auditable in D1.

## AdMob test units

The app defaults to Google's official test ad unit IDs unless release values are supplied with `--dart-define`:

- Android rewarded: `ca-app-pub-3940256099942544/5224354917`
- iOS rewarded: `ca-app-pub-3940256099942544/1712485313`
- Android rewarded interstitial: `ca-app-pub-3940256099942544/5354046379`
- iOS rewarded interstitial: `ca-app-pub-3940256099942544/6978759866`

Release overrides:

- `ADMOB_ANDROID_REWARDED_ID`
- `ADMOB_IOS_REWARDED_ID`
- `ADMOB_ANDROID_REWARDED_INTERSTITIAL_ID`
- `ADMOB_IOS_REWARDED_INTERSTITIAL_ID`

Never ship Google's test App ID or test unit IDs in a production store build.

## AdMob Server-Side Verification

The production callback endpoint is:

`https://<production-worker-host>/v1/rewards/admob/ssv`

Configure this URL for every production rewarded and rewarded-interstitial unit. The client sends the prepared reward token as AdMob `custom_data`. The Worker:

- preserves the original signed query order;
- verifies the ECDSA signature using Google's rotating AdMob public keys;
- validates callback age and future clock skew;
- checks the ad unit against `ADMOB_REWARDED_AD_UNITS`;
- rejects transaction replay;
- marks the prepared reward as server verified;
- grants Coins only when the authenticated app subsequently confirms the same prepared token.

Production confirmation without a valid SSV callback returns `reward_waiting_for_ssv` and grants zero Coins. Staging continues to use the SDK earned-reward callback with official test units so physical-device UX can be tested without production units.

## Production Worker variables and secrets

Non-secret variables:

- `ENVIRONMENT = "production"`
- `ALLOW_TEST_PURCHASE_GRANTS = "false"`
- `REQUIRE_APP_CHECK = "true"`
- `GOOGLE_PLAY_PACKAGE_NAME = "com.devoviastudio.sudoku"`
- `APPLE_BUNDLE_ID = "com.devoviastudio.sudoku"`
- `ADMOB_REWARDED_AD_UNITS = "comma,separated,real,unit,ids"`

Secrets:

- `GOOGLE_PLAY_CLIENT_EMAIL`
- `GOOGLE_PLAY_PRIVATE_KEY`
- `APPLE_IAP_ISSUER_ID`
- `APPLE_IAP_KEY_ID`
- `APPLE_IAP_PRIVATE_KEY`
- existing FCM service-account secrets

Do not put private keys, access tokens or receipts in the repository or client-side Dart defines.

## Required release evidence

- Google Play internal-test purchase screenshots/logs
- App Store sandbox/TestFlight purchase screenshots/logs
- production verifier rejects a fake token/JWS
- duplicate transaction replay rejected
- cancelled purchase grants zero Coins
- pending purchase grants zero Coins until completed
- Android successful consumable is consumed after backend grant
- daily rewarded ad grants once per UTC day
- skipped/no-fill ad grants zero Coins
- career rewarded interstitial has a clear intro and Skip action
- invalid/old/replayed AdMob SSV callbacks grant zero Coins
- production builds contain only real App IDs/unit IDs
