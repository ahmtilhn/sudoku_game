# WorkManager and R8 Follow-up

Reviewed on 2026-07-26 from branch `agent-integrate-codex-firebase`.

## Crash Summary

The Play internal test build with Android `versionCode 2` crashed before `MainActivity` during AndroidX Startup:

- AndroidX Startup
- `WorkManagerInitializer`
- `Failed to create WorkDatabase`

The crash happened in a Play-distributed release build, so release signing, Play packaging, minification, resource shrinking, and transitive AndroidX versions are all part of the risk surface.

## Current Version 3 Hotfix

The `versionCode 3` build intentionally keeps the conservative hotfix:

- `minSdk = 23`
- `targetSdk = 36`
- `compileSdk = 36`
- `androidx.work:work-runtime:2.11.2`
- `androidx.startup:startup-runtime:1.2.0`
- release `isMinifyEnabled = false`
- release `isShrinkResources = false`
- release signing must use `android/key.properties`; debug-key fallback is blocked

Do not re-enable minification in the version 3 hotfix build.

## Dependency Findings

`dependencyInsight` for `releaseRuntimeClasspath` showed:

- `androidx.work:work-runtime` resolves to `2.11.2`.
- Older `work-runtime:2.7.0` is requested by Google Mobile Ads / mediation transitive dependencies and is upgraded by conflict resolution.
- `com.unity3d.ads:unity-ads:4.17.0` requests `work-runtime-ktx:2.7.0`; it is upgraded to `2.11.2`.
- `androidx.room:room-runtime` resolves to `2.7.0` through WorkManager.
- `androidx.startup:startup-runtime` resolves to `1.2.0`; older `1.1.1` is requested through lifecycle/process dependencies and upgraded.

No generated `missing_rules.txt` was found in the current build outputs. Crashlytics mapping file IDs were present, but release minification is disabled, so there is no current R8 mapping file proving a minimized release path.

## Likely Root Causes to Investigate

The exact root cause is still unproven. Plausible causes:

- An older transitive WorkManager/Room/Startup combination in the version 2 build.
- R8 removing or rewriting a Room/WorkManager class needed during eager Startup initialization.
- A minified build-only resource/classpath interaction in Google Mobile Ads or mediation dependencies.
- A device or Play packaging condition that only appears in the Play-delivered artifact.

## Experiment Plan

After version 3 is stable in internal testing:

1. Keep `minSdk = 23`, WorkManager `2.11.2`, and Startup `1.2.0`.
2. Create a separate internal-only build with minify enabled and resource shrinking disabled.
3. Upload mapping files and verify Crashlytics deobfuscation.
4. Test cold start from Play internal testing after uninstalling the old app.
5. If stable, enable resource shrinking in another separate internal build.
6. If a crash returns, inspect mapping, R8 seeds/usage, and generated missing rules.
7. Add the smallest keep rules required by evidence.

Possible rules to test only if evidence points to R8 removing Room/WorkManager classes:

```pro
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.model.** { *; }
-keep class androidx.room.RoomDatabase { *; }
```

Do not add broad keep rules without a reproduced minified crash or R8 evidence.

## Acceptance Criteria for Re-enabling R8

- Play internal test cold start succeeds after a clean install.
- Android Vitals and Crashlytics show no startup crash for the minified build.
- WorkManager initializes without `WorkDatabase` failures.
- Rewarded ad and mediation initialization still work.
- Mapping file upload is verified.
- The build can be reproduced locally and from CI.

