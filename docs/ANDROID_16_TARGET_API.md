# Android 16 / Google Play Target API 36

Reviewed against the current official Google Play and Android documentation on 2026-07-24.

## Google Play deadline

Starting August 31, 2026, new phone/tablet apps and app updates submitted to Google Play must target Android 16, API level 36, or higher.

This project therefore pins:

- `compileSdk = 36`
- `targetSdk = 36`
- `minSdk = 23`

The Android package remains:

- `com.devoviastudio.sudoku`

## Toolchain

The repository uses:

- Android Gradle Plugin 9.0.1
- Gradle 9.1.0
- Java 17

AGP 9.0 supports API level 36.1 and uses Build Tools 36.0.0 by default. No additional AGP upgrade is required only to target API 36.

## Local SDK requirement

Install Android SDK Platform 36 and the latest Android SDK Build-Tools 36.x.x before building.

In Android Studio:

1. Open **Tools > SDK Manager**.
2. Under **SDK Platforms**, install **Android 16 (API 36)**.
3. Under **SDK Tools**, install the latest **Android SDK Build-Tools 36.x.x**.

Then verify:

```powershell
flutter doctor -v
cd android
.\gradlew :app:properties
```

## Android 16 behavior review

Android 16 removes the target-API edge-to-edge opt-out for apps targeting API 36. Flutter layouts must continue to use `SafeArea`, `MediaQuery`, and scaffold insets where content must not overlap system bars.

The current application:

- does not request exact alarms;
- uses inexact notification scheduling;
- requests notification permission at runtime;
- does not use background location;
- does not use broad media permissions;
- does not use foreground services;
- does not lock phone/tablet orientation in the Android manifest.

These choices avoid the Android 16 migration areas that are not needed by Sudoku Duel.

## Release verification

Before uploading an AAB:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test --timeout 60s
flutter build appbundle --release
```

Inspect the built bundle with Android Studio APK Analyzer or bundletool and confirm the manifest reports target SDK 36.
