# Store Product Setup

Consumable Coin products:

- `coins_100`
- `coins_500`
- `coins_1000`
- `coins_5000`
- `coins_10000`
- `coins_50000`
- `coins_100000`

Non-consumable entitlement:

- `no_ads`

Google Play:

- Configure Coin products as managed consumables.
- Configure `no_ads` as a managed non-consumable product.
- Backend verification must not consume `no_ads`.

App Store:

- Configure Coin products as consumable in-app purchases.
- Configure `no_ads` as a non-consumable in-app purchase.

Do not commit real store secrets, service account JSON, private keys, or production ad unit IDs.

