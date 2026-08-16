# Android release services

This document separates the settings verified in source code from settings that exist only in Firebase, Google Cloud, and Google Play Console.

## Supported release command

Android release builds must be explicit production builds. The standard command without release `dart-define` values is intentionally blocked:

```powershell
flutter build appbundle --release
```

Expected guard failure:

```text
Execution failed for task ':app:preReleaseBuild'.
> APP_ENVIRONMENT=production is required for release builds.
```

Use this production AAB command:

```powershell
flutter build appbundle --release `
  --dart-define=APP_ENVIRONMENT=production `
  --dart-define=SOCIAL_BACKEND_URL=https://sudoku-duel-social-production.ilhanahmet246.workers.dev `
  --dart-define=BUILD_COMMIT=<current-git-sha>
```

For the current release candidate:

```powershell
flutter build appbundle --release `
  --dart-define=APP_ENVIRONMENT=production `
  --dart-define=SOCIAL_BACKEND_URL=https://sudoku-duel-social-production.ilhanahmet246.workers.dev `
  --dart-define=BUILD_COMMIT=89ca04117742977f92566d48f6ea75d68d8bf3d7
```

Flutter supplies its own Gradle `dart-defines` project property on every build. The release task validates the effective values supplied by Flutter instead of relying on `android/gradle.properties`, which can be overridden by the Flutter CLI.

The Gradle `preReleaseBuild` validation stops the build when `APP_ENVIRONMENT=production`, `BUILD_COMMIT`, the Firebase project, Android package, Firebase App ID, Play Games project, Play Games game-server OAuth client, or effective production `SOCIAL_BACKEND_URL` is missing or inconsistent.

The backend URL is a public service endpoint, not a secret. It must still be explicitly supplied so a production AAB cannot accidentally use staging, localhost, or an unconfigured social backend.

## Project ownership map

The current console setup deliberately uses two Google Cloud projects:

### Firebase runtime project

```text
Project ID: focus-sweep-503417-d7
Project number: 31445697560
Firebase App ID: 1:31445697560:android:ed951eabf51d75800b2f6d
Package: com.devoviastudio.sudoku
```

This project owns Firebase Authentication, Firebase App Check, Firebase Messaging, Analytics, Crashlytics, and the checked-in `google-services.json` / `firebase_options.dart` configuration.

### Play Games project

```text
Google Cloud project ID: sudoku-503420
Play Games application/project number: 917838292556
Game-server OAuth client:
917838292556-bbq7a36t2kulodpqfd9p3aqkkcs58jhj.apps.googleusercontent.com
```

This project owns the Play Games Android credentials, achievements, leaderboards, and game-server OAuth client.

The two projects may be owned by different Google accounts. The required bridge is the same Play Games game-server OAuth client configured in all three places:

1. `android/app/src/main/res/values/services.xml` as `game_services_web_client_id`;
2. Play Console > Play Games Services > Configuration > game-server credential;
3. Firebase Authentication > Sign-in method > Play Games, together with the current client secret.

The OAuth client secret is console-only and must never be committed, logged, pasted into issues, or added to build variables.

## Why the game-server client is not in google-services.json

`google-services.json` belongs to the Firebase project `focus-sweep-503417-d7`. The game-server OAuth client belongs to the Play Games project `sudoku-503420`. Therefore the Play Games client is not expected to appear in `google-services.json`.

Release validation checks these two configurations independently:

- Firebase project/package/App ID from `google-services.json`;
- Play Games project and game-server OAuth client from `services.xml`.

Do not replace the Firebase `google-services.json` with a file downloaded from the Play Games Cloud project.

## Signing certificates

Google Play uses two different certificate roles:

- **Upload key:** signs the AAB uploaded by the developer.
- **Play app-signing key:** signs APKs delivered to users from Google Play.

Google Play Games Android credentials must use the package name and SHA-1 of the certificate that signs the installed APK. For Play-distributed builds, that is the classic Play app-signing SHA-1 currently recorded for the Android credential:

```text
C0:4C:3A:AB:7D:76:6C:2E:87:C9:53:98:EB:4B:59:97:52:CD:25:A1
```

The upload-key SHA-1 must not be substituted for the Play app-signing SHA-1 when creating the Play Games Android credential. Internal App Sharing may use a different certificate and must not be confused with the normal internal testing track.

## Firebase console requirements

1. Keep the Android Firebase app on `focus-sweep-503417-d7` with package `com.devoviastudio.sudoku`.
2. Enable Anonymous Authentication for guest fallback.
3. Enable the Play Games provider.
4. Configure that provider with the Play Games game-server OAuth client ID shown above and its current secret.
5. Keep the Play app-signing SHA-1 registered on the Firebase Android app where required.
6. Register the Play app-signing SHA-256 in Firebase App Check with Play Integrity before enforcement is enabled.

Rotating a client secret requires updating the Firebase Play Games provider immediately. The secret is not used or stored by the Android application.

## Play Games console requirements

1. Keep the Play Games project/application ID `917838292556`.
2. Keep an Android credential for `com.devoviastudio.sudoku` using the certificate that signs the tested installation path.
3. Keep the game-server credential linked to:

```text
917838292556-bbq7a36t2kulodpqfd9p3aqkkcs58jhj.apps.googleusercontent.com
```

4. Enable the tester account or internal testing release track while the Play Games project changes are unpublished.
5. Publish the Play Games Services configuration when it is ready for all users.

These console associations and secrets cannot be verified from repository code alone.

## Verification

Validate source configuration before building:

```powershell
.\tool\verify_android_release_config.ps1
```

Build the production AAB:

```powershell
flutter build appbundle --release `
  --dart-define=APP_ENVIRONMENT=production `
  --dart-define=SOCIAL_BACKEND_URL=https://sudoku-duel-social-production.ilhanahmet246.workers.dev `
  --dart-define=BUILD_COMMIT=<current-git-sha>
```

Inspect the produced artifact:

```powershell
.\tool\verify_online_aab.ps1 `
  -Path ".\build\app\outputs\bundle\release\app-release.aab"
```

The certificate printed from the local AAB is the upload certificate. Google Play re-signs delivered APKs with the Play app-signing certificate.

## Runtime diagnostics

The Android bridge reports the installed package name, Play Games project ID, runtime signing SHA-1, installer package, app version, Google Play services status, and API status code. Dart preserves these details in `PlatformGameServicesException` instead of discarding `PlatformException.details`.

For a Play Store installation, the runtime signing SHA-1 must match the Android credential selected for that distribution path. A mismatch indicates that the Play Games Android credential or tested distribution path is using a different certificate.

## Official references

- Google Play Games Services setup: https://developer.android.com/games/pgs/console/setup
- Google Play Games server-side access: https://developer.android.com/games/pgs/android/server-access
- Google Play Games troubleshooting: https://developer.android.com/games/pgs/android/troubleshooting
- Firebase Authentication with Play Games: https://firebase.google.com/docs/auth/android/play-games
- Firebase App Check with Play Integrity: https://firebase.google.com/docs/app-check/android/play-integrity-provider
