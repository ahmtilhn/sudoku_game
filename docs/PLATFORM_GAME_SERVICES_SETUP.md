# Google Play Games Services v2 and Apple Game Center Setup

Reviewed against the current official Google and Apple documentation on 2026-07-24.

## Permanent identities

- Android application ID: `com.devoviastudio.sudoku`
- iOS bundle ID: `com.devoviastudio.sudoku`
- Flutter MethodChannel: `com.devoviastudio.sudoku/game_services`

These IDs must match the store records, OAuth credentials, signing certificates, and installed binaries exactly.

## Google Play Games Services v2

### 1. Create or link the Play Games project

In Google Play Console:

1. Open the Sudoku application with package `com.devoviastudio.sudoku`.
2. Open **Grow users > Play Games Services > Setup and management > Configuration**.
3. Create a new Play Games Services project or link the correct Google Cloud project.
4. Add the game details and save the Play Games numeric project ID.
5. Replace `game_services_project_id` in:
   `android/app/src/main/res/values/services.xml`.

The checked-in value `0000000000` intentionally disables Play Games initialization.

### 2. Configure Android credentials

Create Android OAuth credentials for every certificate that can sign an installed build:

- local debug certificate;
- Play App Signing certificate;
- upload/release certificate if direct signed builds are tested outside Play.

For each credential, use:

- package name `com.devoviastudio.sudoku`;
- the exact SHA-1 fingerprint from the matching certificate.

Useful checks:

```powershell
cd android
.\gradlew signingReport
```

Also copy the Play App Signing SHA-1 from Play Console. A package/SHA mismatch is the most common reason automatic authentication works locally but fails after Play distribution, or the reverse.

### 3. Configure server-side access

The cross-platform Sudoku Duel backend must verify Play Games identity before linking an account.

1. Create a **Web application** OAuth client in the linked Google Cloud project.
2. Configure the Play Games game-server credential with that web client.
3. Replace `game_services_web_client_id` in `services.xml`.
4. The Android bridge calls `requestServerSideAccess(..., false)` and returns a one-time server auth code.
5. Send that code directly to the backend over HTTPS.
6. The backend exchanges and verifies the code with Google. Never trust a client-supplied player ID without this verification.

Do not log or persist unused one-time auth codes.

### 4. Create platform achievements and leaderboard

Create equivalent products in Play Console and App Store Connect.

Minimum initial set:

- leaderboard: global competitive rating;
- achievement: first online win.

Replace Android placeholders:

- `leaderboard_global_rating`;
- `achievement_first_win`.

Additional achievements should use internal cross-platform keys that map to separate Google and Apple IDs in the backend/configuration layer.

### 5. Enable testers and publish configuration

Before public release:

1. Add Play Games test accounts.
2. Publish the Play Games configuration to testers.
3. Install the app from a Play testing track using the matching Play-signed artifact.
4. Confirm automatic authentication.
5. Confirm friend consent, profile comparison, leaderboard, achievement, and server auth code flows.
6. Publish the Play Games Services configuration before or with the production app.

### Android runtime bridge

Supported methods:

- configuration and authentication status;
- explicit sign-in retry;
- local player profile;
- consent-based friends list;
- native compare-profile view;
- native leaderboard and achievement views;
- score submission;
- achievement unlock;
- one-time server auth code.

Play Games does not provide current real-time or turn-based multiplayer APIs for new games. Sudoku matches, username search, challenges, recent opponents, and cross-platform friends therefore use the shared backend.

## Apple Game Center

### 1. Register and enable the App ID

In Apple Developer and App Store Connect:

1. Register or update the App ID `com.devoviastudio.sudoku`.
2. Enable the **Game Center** capability.
3. Regenerate development and distribution provisioning profiles if necessary.
4. In App Store Connect, enable Game Center for the Sudoku app version.

The repository includes `Runner.entitlements` with the Game Center entitlement and attaches it to Debug, Profile, and Release through the Flutter xcconfig files.

### 2. Configure Game Center products

In App Store Connect create:

- global rating leaderboard;
- first online win achievement;
- localized titles/descriptions/artwork as required.

Replace the placeholder build settings in both:

- `ios/Flutter/Debug.xcconfig`;
- `ios/Flutter/Release.xcconfig`.

Keys:

- `INFOPLIST_KEY_SudokuLeaderboardGlobalRating`;
- `INFOPLIST_KEY_SudokuAchievementFirstWin`.

### 3. Friend privacy permission

The build settings inject `NSGKFriendListUsageDescription`:

> Sudoku Duel uses your Game Center friends to help you find familiar players and send challenges.

Friend permission is requested only when the player opens social features. Game Center returns only friends allowed by Apple's scoped privacy rules.

Use `gamePlayerID` for the identity of a player inside this game. Do not persist aliases as identity keys.

### 4. Backend identity verification

The iOS bridge returns:

- `gamePlayerID`;
- public key URL;
- signature;
- salt;
- timestamp;
- bundle identifier.

Send the complete response to the backend over HTTPS. The backend must retrieve Apple's public key, validate the signature payload exactly as documented, validate the bundle ID, and reject stale/replayed timestamps.

### 5. Test with sandbox accounts

Use physical Apple devices and Game Center sandbox testing:

1. Confirm the device is signed into a Game Center tester account.
2. Install a development/TestFlight build signed with the Game Center entitlement.
3. Authenticate and verify `gamePlayerID`.
4. Test friend-list permission and denial.
5. Test native player profile, leaderboard, achievements, and recent players.
6. Verify identity signatures on the backend.
7. Repeat with multiple sandbox users.

## Flutter social screen

The platform screen is challenge-first and exposes:

- platform sign-in;
- local platform profile;
- platform friends;
- Game Center recent players where available;
- native platform profiles;
- native leaderboard and achievements;
- a primary Challenge button.

Challenge delivery stays disabled until the shared backend and push credentials are deployed. This is intentional: a platform friend is not by itself an authoritative cross-platform Sudoku Duel account.

## Release checks

- no `REPLACE_...` platform identifiers remain;
- Play Games numeric project ID is real;
- all signing SHA-1 fingerprints are configured;
- Play Games testers work from the Play testing track;
- iOS provisioning profiles include Game Center;
- Game Center is enabled in App Store Connect;
- leaderboard and achievement IDs match both console definitions;
- backend verifies Google auth codes and Apple identity signatures;
- platform IDs are never displayed or exposed in public APIs;
- friend access is consent-based;
- privacy policy and store disclosures describe the social graph and platform identifiers.

## Official references

- Google Play Games Services v2 setup and authentication
- Google Play Games Android friends
- Google Play Games leaderboards and achievements
- Google Play Games server-side access
- Apple GameKit player authentication
- Apple Game Center friend access and scoped player identifiers
- Apple Game Center leaderboards and achievements
- Apple identity verification signatures
