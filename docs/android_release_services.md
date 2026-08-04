# Android release services

This document separates the settings that are verified in source code from the settings that exist only in Firebase and Google Play Console.

## Supported release command

The Android project embeds the staging social backend in `android/gradle.properties`, so the standard Flutter command is supported:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

The Gradle `preReleaseBuild` validation stops the build when the Firebase project, Android package, Firebase App ID, Play Games server OAuth client, or `SOCIAL_BACKEND_URL` is missing or inconsistent.

The backend URL is a public service endpoint, not a secret. Production builds can override it with `--dart-define=SOCIAL_BACKEND_URL=https://...` when a production worker is available.

## Signing certificates

Google Play uses two different certificate roles:

- **Upload key:** signs the AAB uploaded by the developer.
- **Play app-signing key:** signs APKs delivered to users from Google Play.

Google Play Games Android credentials must use the package name and SHA-1 of the certificate that signs the installed APK. For Play-distributed builds, that is the **classic Play app-signing SHA-1**, currently:

```text
53:B0:F0:FF:89:6C:50:AE:B0:86:F2:04:A2:2E:ED:E2:9F:1B:F3:0B
```

The upload-key SHA-1 must not be substituted for the Play app-signing SHA-1 when creating the Play Games Android credential.

## Firebase requirements

The Android Firebase application must remain:

```text
Project ID: focus-sweep-503417-d7
Project number: 31445697560
Firebase App ID: 1:31445697560:android:ed951eabf51d75800b2f6d
Package: com.devoviastudio.sudoku
```

Firebase project settings must contain the Play app-signing SHA-1. Firebase App Check with Play Integrity must be registered with the Play app-signing SHA-256.

The checked-in `google-services.json` is validated for the project, package, App ID, and web OAuth client. An Android `client_type: 1` entry is not required by the build because the Play Games Android OAuth credential is linked to the game in Play Console and is not guaranteed to be emitted in `google-services.json`.

## Play Games requirements

In Play Games Services configuration:

1. Link an Android credential for `com.devoviastudio.sudoku` using the classic Play app-signing SHA-1.
2. Link the game-server credential to the same web client used by Firebase Authentication:

```text
31445697560-srkgbb34irg821mamsq0tnd6hvr4j8li.apps.googleusercontent.com
```

3. Enable the tester account or the internal testing release track while the Play Games project changes are unpublished.
4. Publish the Play Games Services configuration when it is ready for all users.

These console associations cannot be verified from the repository alone.

## Verification

Validate source configuration before building:

```powershell
.\tool\verify_android_release_config.ps1
```

Build normally:

```powershell
flutter build appbundle --release
```

Inspect the produced artifact:

```powershell
.\tool\verify_online_aab.ps1 `
  -Path ".\build\app\outputs\bundle\release\app-release.aab"
```

The certificate printed from the local AAB is the upload certificate. Google Play re-signs delivered APKs with the Play app-signing certificate.

## Runtime diagnostics

The Android bridge reports the installed package name, Play Games project ID, runtime signing SHA-1, installer package, app version, Google Play services status, and API status code. Dart preserves these details in `PlatformGameServicesException` instead of discarding `PlatformException.details`.

For a Play Store installation, the runtime signing SHA-1 should match the classic Play app-signing SHA-1 above. A mismatch indicates that the Play Games Android credential or the tested distribution path is using a different certificate.

## Official references

- Google Play Games Services setup: https://developer.android.com/games/pgs/console/setup
- Google Play Games troubleshooting: https://developer.android.com/games/pgs/android/troubleshooting
- Firebase Authentication with Play Games: https://firebase.google.com/docs/auth/android/play-games
- Firebase App Check with Play Integrity: https://firebase.google.com/docs/app-check/android/play-integrity-provider
