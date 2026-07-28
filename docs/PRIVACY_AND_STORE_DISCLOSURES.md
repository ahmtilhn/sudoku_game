# Privacy and Store Disclosures

This document is a release checklist, not a substitute for legal review.

## Data processed by the app/backend

- Firebase UID and authentication provider.
- Email address only when the player protects the account.
- Email-verification status; passwords are handled by Firebase Authentication and are never stored by Sudoku Duel.
- Public Friend ID, username, display name, discoverability preference and optional platform game-services display name.
- Friends, challenges, recent opponents, matchmaking tickets and device push tokens.
- Match board events, scores, mistakes, timeout/forfeit status, rating and match history.
- Coin balance, immutable Coin ledger, escrow funding/refunds, reward claims, achievement grants and purchase verification identifiers.
- Google Play purchase token/order metadata or Apple signed transaction/original transaction metadata used for server verification and replay prevention.
- AdMob rewarded-ad SSV transaction, ad unit, prepared reward token, reward item/amount and verification timestamp.
- Optional analytics/crash diagnostics according to in-app privacy toggles.
- Account-deletion tombstone containing the deleted Firebase UID and deletion timestamp solely to prevent recreation/reward abuse.

## Data not supported by the product

- No real-money withdrawal or cash conversion.
- No user-to-user Coin transfer.
- No physical prize redemption.
- No sale of chat/messages because the app has no user chat feature.
- No storage of raw passwords or payment card details.

## Google Play Data safety review

Confirm declarations for:

- Account information: optional email and user ID.
- App activity: gameplay, interactions, achievements and match history.
- App information/performance: crash logs and diagnostics when enabled.
- Device or other IDs: Firebase/App Check, advertising identifiers subject to consent, push token.
- Financial information: purchase history/transaction identifiers; Google Play processes payment details.
- Data encryption in transit and account-deletion request availability.
- Purposes: app functionality, account management, fraud prevention/security, analytics, advertising and developer communications where applicable.

## App Store privacy review

Confirm App Privacy answers for:

- Contact Info: email address, linked to the account when protection is enabled.
- User Content/Identifiers: username, Friend ID, Firebase UID.
- Purchases: product and transaction history.
- Usage Data: gameplay and advertising interaction.
- Diagnostics: crashes/performance when enabled.
- Device ID/Advertising Data: according to ATT/UMP consent and enabled SDK behavior.

## Account deletion

The app exposes Player account > Delete player account. The flow:

1. Requires the exact word `DELETE`.
2. Reauthenticates protected email/password users.
3. Rejects deletion during an active online match until it is finished/forfeited.
4. Deletes the server player row and cascading wallet/social/match data.
5. Stores a minimal abuse-prevention tombstone.
6. Deletes the Firebase Authentication user and creates a new separate guest session.

Privacy policy and support procedures must explain the tombstone retention purpose and retention period. Define a manual support route for the rare case where Firebase deletion fails after server data deletion.

## Advertising and consent

- Development/staging uses official Google test ad units.
- Production uses real AdMob App IDs/unit IDs.
- UMP consent is requested before ad loading where required.
- ATT is requested on iOS only when applicable.
- Privacy options remain accessible from Settings when required.
- Rewarded ads are optional and disclose the exact Coin reward before showing.
- Career rewarded interstitial has an explicit Skip action.
- Production rewards require AdMob SSV; invalid/replayed callbacks grant zero Coins.

## Store product/review metadata

For every Coin product include:

- exact Coin amount;
- consumable classification;
- localized display name/description;
- clear statement that Coins have no cash value and cannot be transferred;
- review screenshot showing the Coin Store and localized storefront price;
- review notes describing server verification and account-protection requirement.

## Final evidence

- Public privacy-policy URL opens without authentication.
- Support/account-deletion instructions are reachable.
- Android Data safety and iOS App Privacy answers match actual SDK/network behavior.
- Consent behavior tested for EEA, UK, US states and non-consent regions using test geography where supported.
- Account create/link/sign-in/reset/verify/delete scenarios recorded on Android and iOS.
