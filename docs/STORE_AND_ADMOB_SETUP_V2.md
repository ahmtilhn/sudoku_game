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

1. Create one-time in-app products with the exact IDs above.
2. Activate the products and add license-test accounts.
3. Upload a signed internal-testing App Bundle using the production application ID.
4. Install from the Play internal-testing link; sideloaded builds do not exercise the complete Play Billing sandbox path.
5. Verify pending, successful, cancelled and repeated consumable purchases.
6. Before production, configure Google Play Developer API server credentials and replace staging-only purchase grants with server verification.

## iOS test path

1. Create consumable In-App Purchases with the exact IDs above.
2. Complete localization, pricing and review metadata for every product.
3. Create StoreKit sandbox testers.
4. Test from a development/TestFlight build signed with the correct bundle ID and capability.
5. Verify successful, cancelled, interrupted and repeated consumable purchases.
6. Before production, configure App Store Server API credentials and signed-transaction verification.

## Current safety behavior

- `ENVIRONMENT=staging` plus `ALLOW_TEST_PURCHASE_GRANTS=true` permits sandbox-flow integration tests.
- `ENVIRONMENT=production` rejects purchase grants until real Google/Apple server verification is implemented and configured.
- Transaction IDs and verification hashes are unique in D1 to prevent simple replay.
- The client completes a store purchase only after the backend grants Coins.

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

## Reward verification gate

Staging confirms rewards after the official SDK earned-reward callback so physical-device UX can be tested.

Production confirmation endpoints are deliberately blocked until AdMob Server-Side Verification is connected. Do not remove this guard and do not grant production Coins solely from a client callback.

## Required release evidence

- Google Play internal-test purchase screenshots/logs
- App Store sandbox/TestFlight purchase screenshots/logs
- duplicate transaction replay rejected
- cancelled purchase grants zero Coins
- pending purchase grants zero Coins until completed
- daily rewarded ad grants once per UTC day
- skipped/no-fill ad grants zero Coins
- career rewarded interstitial has a clear intro and Skip action
- production builds use real ad units only after AdMob policy/consent review
