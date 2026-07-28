# Account Protection and Release Setup

## Purpose

Sudoku Duel starts offline/online play with a Firebase anonymous account, but paid Coin purchases are blocked until the player protects that same Firebase UID with email/password or signs in to an existing protected account. Linking preserves the server wallet, Friend ID, username, friends, rating and match history.

## Firebase Console

1. Open Firebase Authentication for project `focus-sweep-503417-d7`.
2. Enable the Email/Password provider.
3. Configure the public-facing sender name and support email.
4. Add the production Android/iOS app domains and email-action domain.
5. Customize verification and password-reset templates.
6. Verify that anonymous authentication remains enabled for first-launch play.

## Test matrix

- New guest links an unused email; Firebase UID stays unchanged.
- Wallet, Friend ID and rating are unchanged after linking.
- Verification email is sent and can be resent.
- Unverified password account cannot start a paid Coin purchase.
- Verified account can start a store sandbox purchase.
- Reinstall/new device can sign in and recover the same wallet/profile.
- Wrong password, invalid email, weak password, duplicate email and rate limiting show safe errors.
- Signing out creates a separate guest and does not merge wallets.
- Signing back in restores the protected account.

## Store review notes

Explain that:

- account protection is optional for free gameplay;
- it becomes required only before buying consumable Coins;
- users can recover paid Coins and online identity on another device;
- Coins cannot be transferred, cashed out or redeemed for real-world value;
- online entry is a fixed game fee and rewards remain entirely inside the Sudoku game.

## Production gates

- Email/Password provider enabled.
- Verification/password-reset email links tested on Android and iOS.
- Privacy policy describes account email, Firebase UID, Friend ID, match history, purchases and rewarded-ad verification.
- Google Play Data safety and App Store privacy disclosures updated.
- Account deletion workflow and support contact defined before launch.
