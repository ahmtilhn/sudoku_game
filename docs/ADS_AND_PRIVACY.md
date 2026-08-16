# Ads, UMP, Unity Ads, Meta Audience Network, and Meta App Events

Reviewed against the current Google, Unity, Meta adapter, Apple ATT, and package documentation on 2026-07-24.

## Runtime architecture

Sudoku Duel uses Google Mobile Ads as the only client ad request layer.

- AdMob owns the Android and iOS ad units.
- Google UMP is requested on every app launch.
- The app does not initialize Mobile Ads or load an ad until `canRequestAds()` is true.
- Rewarded ads are used for a hint or a career continuation only after the SDK confirms the reward callback.
- Unity Ads and Meta Audience Network are loaded only through AdMob mediation adapters.
- Meta Audience Network is configured as bidding-only.
- Meta App Events is a separate measurement SDK. It remains disabled in the checked-in configuration until real Meta credentials and an explicit production build flag are supplied.

## Checked-in AdMob release identifiers

The checked-in platform files and release defaults use production AdMob identifiers:

- Android AdMob application ID: `ca-app-pub-8422988604275177~6950938184`
- iOS AdMob application ID: `ca-app-pub-8422988604275177~3293784266`
- Android rewarded unit: `ca-app-pub-8422988604275177/3474727600`
- Android rewarded interstitial unit: `ca-app-pub-8422988604275177/4787809275`
- iOS rewarded unit: `ca-app-pub-8422988604275177/3366916396`
- iOS rewarded interstitial unit: `ca-app-pub-8422988604275177/4982984468`

Debug builds still fall back to Google's official test units in `AdsService`; release
builds use the production defaults above unless overridden with dart defines.
Never publish a store build that contains Google's test App ID or test unit IDs.

Meta placeholders are deliberately invalid and all automatic Meta collection flags are false. This prevents accidental event transmission from development builds.

## AdMob console checklist

Create or link two AdMob apps:

1. Android package: `com.devoviastudio.sudoku`
2. iOS bundle ID: use the final App Store bundle ID after it is confirmed in Xcode and App Store Connect.

For each app:

1. Create a rewarded ad unit.
2. Copy the real application ID into:
   - Android: `android/app/src/main/res/values/services.xml`
   - iOS: `ios/Runner/Info.plist`
3. Supply rewarded unit IDs at build time:

```bash
flutter build appbundle \
  --dart-define=ADMOB_ANDROID_REWARDED_ID=ca-app-pub-REAL/REAL

flutter build ipa \
  --dart-define=ADMOB_IOS_REWARDED_ID=ca-app-pub-REAL/REAL
```

4. Keep Google test units or registered test devices during development.
5. Create a GDPR message in Privacy & messaging.
6. Configure applicable US state messages.
7. Ensure Unity Ads and Meta are included in the consent message's ad technology / partner disclosures where required.
8. Publish the privacy message before release.
9. Verify the in-app **Ad privacy choices** entry point appears when UMP reports it as required.

## UMP behavior

The application:

- requests fresh consent information on each launch;
- shows the consent form when required;
- checks `canRequestAds()` before Mobile Ads initialization;
- keeps ads unavailable when consent has not been resolved;
- exposes UMP privacy options from Settings when required;
- requests ATT on iOS only after UMP is resolved and before ad initialization.

UMP does not automatically guarantee that every mediated network receives every legally required consent signal. Review each partner's documentation and the AdMob mediation privacy guidance before release.

## Unity Ads mediation checklist

The Flutter Unity adapter package is installed, but console credentials are still required.

1. Create or select the Unity project in Unity Dashboard.
2. Create Android and iOS game entries.
3. Create rewarded placements / ad units.
4. In AdMob Mediation, add Unity Ads to the rewarded mediation group.
5. Enter the Unity game IDs and placement IDs requested by AdMob.
6. Enable Unity test mode while validating.
7. Confirm the Unity adapter appears as `ready` in Mobile Ads initialization status.
8. Disable test mode only for the release build.
9. Review Unity privacy and age-related settings for the intended audience.

The current adapter requires Android API 23+ and iOS 13+; this project meets those minimums.

## Meta Audience Network mediation checklist

The Flutter Meta mediation adapter package is installed. Meta mediation is bidding-only.

1. Create the app in Meta for Developers.
2. Add the Android package and iOS bundle ID.
3. Create the Audience Network property and rewarded placement.
4. Connect Meta bidding in the AdMob rewarded mediation group.
5. Map the Android and iOS placement IDs.
6. Add the app-ads.txt entry Meta provides to the developer website.
7. Test with Meta test devices / test mode.
8. Verify the Meta adapter is `ready` in AdMob's mediation test suite.
9. Do not attempt to configure a traditional Meta waterfall entry when the current adapter supports bidding only.

## Meta App Events checklist

Meta App Events is included so future Facebook/Instagram app campaigns can attribute installs and events. It is not automatically enabled in development.

Replace the placeholders:

- Android `facebook_app_id` and `facebook_client_token` in `services.xml`.
- iOS `FacebookAppID` and `FacebookClientToken` in `Info.plist`.
- Add the real `fb<APP_ID>` URL scheme to Android/iOS if required by the final Meta feature set.

After the Meta app is configured and privacy review is complete, enable the SDK only in a production build:

```bash
flutter build appbundle \
  --dart-define=META_SDK_ENABLED=true \
  --dart-define=META_ADVERTISER_TRACKING_ENABLED=false
```

Set advertiser tracking to true only where the required permission and consent states allow it. Do not send email addresses, phone numbers, platform player IDs, or other direct identifiers as custom event parameters.

Suggested server-validated or low-risk events for a later phase:

- tutorial completed;
- puzzle completed;
- difficulty reached;
- achievement unlocked;
- challenge sent / accepted;
- rewarded ad completed.

Do not log virtual currency purchases or competitive results solely from untrusted client claims.

## iOS requirements

`Info.plist` contains:

- the production Google Mobile Ads application ID;
- `NSUserTrackingUsageDescription`;
- the current Google-published SKAdNetwork list;
- disabled Meta automatic collection flags.

Before each release, compare the checked-in SKAdNetwork list against the latest Google Mobile Ads iOS quick-start page and any partner-specific additions.

## Release blocker checklist

A release is blocked until all of the following are true:

- real Android and iOS AdMob application IDs are installed;
- real rewarded ad unit IDs are supplied;
- UMP messages are published;
- the privacy policy describes Google, Unity, Meta, advertising identifiers, consent choices, and rewarded ads;
- Unity and Meta mediation credentials are entered in AdMob;
- AdMob mediation test suite shows the intended adapters;
- all test modes are disabled for production;
- Meta placeholders are replaced or the Meta SDK dependency is removed;
- ATT and UMP behavior is tested on physical iOS devices;
- the store privacy/data safety declarations match actual SDK behavior.

## Official references

- Google Mobile Ads Flutter quick start
- Google UMP Flutter guide
- Google rewarded ads guide
- Google AdMob mediation guides
- Google Unity Ads Flutter mediation guide
- Google Meta Audience Network Flutter mediation guide
- Google iOS SKAdNetwork / privacy strategy guide
- Apple App Tracking Transparency documentation
- Meta App Events setup documentation
