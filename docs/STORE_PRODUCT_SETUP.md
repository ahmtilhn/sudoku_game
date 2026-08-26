# Store Product Setup

## Consumable Coin products

The following identifiers must be configured as consumable products on both Google Play and App Store Connect:

- `coins_100`
- `coins_500`
- `coins_1000`
- `coins_5000`
- `coins_10000`
- `coins_50000`
- `coins_100000`

## Non-consumable entitlement

- Google Play: `no_ads`
- App Store: `sudoku_duel_no_ads`

## Google Play

- Configure Coin products as managed consumables.
- Configure `no_ads` as a managed non-consumable product.
- The backend verifies the purchase before the client consumes a Coin token.
- Backend verification must never consume `no_ads`.

## App Store

- Bundle identifier: `com.devovia.sudokuduel`.
- Configure every Coin product above as a **Consumable** in-app purchase.
- Configure `sudoku_duel_no_ads` as a **Non-Consumable** in-app purchase.
- Enable the **In-App Purchase** capability for the App ID / Runner target used to sign the production build.
- The Flutter client uses StoreKit 2. Do not force StoreKit 1 during application startup.
- A charged StoreKit transaction is completed only after the backend has securely verified and applied the purchase. Unfinished transactions are recovered before another charge for the same product can start.
- App Store Server API verification requires the production worker secrets `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY`, and `APPLE_ROOT_CERTIFICATES_PEM`.
- `APPLE_BUNDLE_ID` in the production worker must remain `com.devovia.sudokuduel`.

Do not commit real store secrets, service account JSON, private keys, or production signing credentials.
