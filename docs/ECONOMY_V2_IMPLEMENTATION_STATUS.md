# Economy V2 Implementation Status

Updated for branch `codex-authoritative-online-duel`.

## Implemented in code

### Server-authoritative wallet

- One-time 1,000 Coin starter grant per backend player account.
- Immutable Coin ledger with idempotency keys and balance-after values.
- Wallet snapshot and ledger APIs.
- Negative-balance guard.
- Daily login reward: +50 Coin once per UTC day.
- Daily rewarded-ad preparation and confirmation: +50 Coin.
- Career rewarded-interstitial preparation and confirmation: +25 Coin.
- Career reward preparation cap: 20 per UTC day.
- Achievement reward thresholds and automatic one-time grants.
- Staging purchase grants with transaction replay protection.
- Production Google Play ProductPurchaseV2 verification, matching-product/state checks and server-side consumption attempt.
- Production App Store Server API Get Transaction Info verification with transaction, product, bundle, ownership, type and revocation checks.
- Production AdMob SSV callback verification, ad-unit allowlist, callback-age checks and transaction replay protection.
- Purchase/ad verification audit columns added in migration `0014_production_verification.sql`.

### Durable player account and deletion

- Guest Firebase accounts can be linked to email/password without changing the Firebase UID, wallet, Friend ID, rating, friends or history.
- Existing protected accounts can sign in on another installation/device.
- Verification-email resend, account refresh, password reset and sign-out-to-guest flows.
- Responsive account-protection screen and persistent Home/Coin Store entry points.
- Coin Store purchase buttons are disabled for anonymous players.
- Backend purchase verification also rejects anonymous accounts and requires verified email for password accounts.
- Paid balances therefore cannot be intentionally granted to an unrecoverable guest account.
- In-app permanent account deletion reauthenticates protected users and rejects deletion during an active online match.
- Server wallet, social and gameplay data are removed through the player cascade; Firebase Authentication deletion follows on the device.
- A minimal deletion tombstone prevents the deleted Firebase UID from being recreated for starter-grant/reward abuse.
- Account deletion schema is added in migration `0015_account_deletion.sql`.

### Online entry escrow

- A player needs at least 100 Coin to enter matchmaking.
- Queue cancellation is free.
- When a compatible pair is created, D1 deducts 100 Coin from each player and creates a 200 Coin escrow.
- Winner receives the 200 Coin pot.
- Draw/pre-start terminal states refund 100 Coin to each player.
- Forfeit/disconnect winner settlement uses the same escrow payout.
- Direct friend-challenge matches also require and fund the same escrow.
- Guard triggers abort partial or negative entry-fee operations.
- A database uniqueness guard blocks duplicate active rooms and duplicate rematch charges for the same player pair.

### Rematch and result flow

- Responsive result surface with score, opponent, entry, pot, balance, rating and finish reason.
- Actions: challenge again, find new match, add friend, main menu.
- Rematch and new-match actions require at least 100 Coin; exactly 100 is valid.
- Ten-second rematch invitation with accept, decline, timeout and insufficient-balance states.
- Rematch acceptance rechecks both balances before creating a funded room.
- In-result polling and best-effort FCM rematch notification support.
- Notification tap can open an actionable ten-second accept/decline dialog.

### Turn clarity and responsive UI

- Opponent-turn board and number pad are desaturated and dimmed.
- Opponent-turn controls are non-interactive without repeated snackbars.
- Local turn restores normal colors and gives haptic feedback.
- Non-color text/icon cues remain visible.
- Matchmaking, home, result, Coin Store, wallet history, settings, account protection and career reward surfaces use constraint-driven layouts.
- Content width is bounded on tablets/expanded windows.

### Coin Store and ads

- Consumable product IDs from `coins_100` through `coins_100000`.
- Localized price/title/description read from Google Play or App Store.
- Purchase stream starts before product query.
- Purchase is completed only after the backend grant succeeds.
- Android duplicate/server-side consumption is tolerated without hiding the verified wallet result.
- Official Google test rewarded and rewarded-interstitial ad IDs are the default for development/staging.
- AdMob server-side verification options are applied before an ad is shown.
- Career completion shows an explicit reward explanation and Skip action before the ad.

### Player identity and discoverability

- First online onboarding asks for a display name and unique username.
- Google Play Games/Game Center display name can be suggested when available.
- Immutable Friend ID is shown and copyable in Settings.
- Username/display-name/exact-Friend-ID search.
- Discoverability preference.
- Username normalization, uniqueness, reserved-name and basic unsafe-name validation.
- Legacy profile refreshes cannot overwrite the confirmed custom name.

### Platform preparation

- Android minimum SDK raised to 24 for current billing support.
- iOS minimum version raised to 13.
- iOS bundle ID aligned with Firebase/App Store configuration.
- iOS entitlements and APS environment are wired during CocoaPods installation.
- Validation and guarded staging-deployment PowerShell scripts were added.
- Production Worker example lists all required Google Play, Apple IAP, AdMob SSV, Firebase/App Check and FCM variables/secrets without committing values.
- Privacy/store disclosure and account-protection release checklists were added.

## Not yet verified

The implementation was committed through GitHub, but the following have not yet been run successfully against the final combined branch:

- `flutter pub get`
- Dart formatter on the final source set
- `flutter analyze`
- full Flutter test suite
- Worker TypeScript typecheck
- Worker test suite
- local D1 migration application from a clean database
- remote migrations `0005` through `0015`
- deployment of the new Worker entrypoint
- physical Android/iOS cross-platform tests
- Firebase email/password account-linking and account-deletion tests with the provider enabled
- Google Play internal-test purchases and consumption/replay tests
- App Store sandbox/TestFlight purchases and replay/revocation tests
- AdMob SSV signed callback tests with real production ad units

A GitHub-hosted validation workflow was attempted, but both jobs failed before the first checkout step and produced no job logs. It was removed so an infrastructure-level red check would not be confused with a code validation result. Local validation remains mandatory.

Do not promote this branch until those checks pass.

## External console/configuration required before production

These are console/credential actions and cannot be completed by repository code alone:

- Enable Email/Password authentication in Firebase Authentication.
- Create and activate all Coin products in Google Play Console and App Store Connect.
- Give the Google Play verification service account API/app access and set Worker secrets.
- Create an App Store Connect In-App Purchase key and set Worker secrets.
- Configure the production AdMob SSV URL on every rewarded ad unit and supply the real ad-unit allowlist.
- Replace Google's test App ID/unit IDs in the production build.
- Enable App Check enforcement after valid staging traffic is confirmed.
- Configure/verify FCM service-account secrets and APNs credentials.
- Finish localization of all newly introduced economy/rematch/profile/account strings across supported locales.
- Publish the privacy policy and complete store data disclosures, purchase metadata and review notes.

## First validation command

From the Windows project root:

```powershell
.\scripts\validate_economy_v2.ps1
```

After that passes and formatting changes are committed, deploy staging with:

```powershell
.\scripts\deploy_economy_v2_staging.ps1
```
