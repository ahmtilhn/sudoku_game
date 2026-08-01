# No Ads Entitlement

`no_ads` is a non-consumable entitlement, not a Coin product.

Backend:

- Verify store purchase server-side.
- Grant `player_entitlements.entitlement_key = 'no_ads'`.
- Use transaction/hash replay protection.
- Return wallet entitlements as `{ "noAds": true }`.
- Do not consume Android `no_ads` purchases.

Client:

- Query `no_ads` with store product details separately from Coin packages.
- Purchase through the non-consumable flow.
- Restore purchases through the store SDK.
- When owned, block ad SDK load/show attempts and hide rewarded ad offers.

Rewarded-ad economy endpoints stay server-authoritative and dormant for entitled users through client-side hiding plus service guards.

