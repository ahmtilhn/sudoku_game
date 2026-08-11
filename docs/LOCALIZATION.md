# Localization workflow

English is the canonical source language for the application.

## Supported app locales

The Flutter app, Android locale configuration, and iOS bundle currently declare:

- English
- Turkish
- German
- French
- Spanish
- Portuguese
- Italian
- Dutch
- Polish
- Russian
- Ukrainian
- Arabic
- Hindi
- Indonesian
- Japanese
- Korean
- Simplified Chinese
- Traditional Chinese
- Thai
- Vietnamese
- Bangla
- Urdu

The interface follows the device or per-app language setting. If a translation is missing, the app falls back to English.

## Android: Google Play app strings translation using Gemini

This project is prepared for Google Play's **App strings translation using Gemini** feature. Flutter does not normally expose Dart UI text through Android resources, so all visible app text is mirrored in:

`android/app/src/main/res/values/strings.xml`

At startup, the Android method channel reads the localized Android resources and passes them to Flutter. This lets translations that Google Play injects into the Android App Bundle appear inside the Flutter UI.

### Enable it in Play Console

1. Build and upload an Android App Bundle to a **draft release**.
2. Open Play Console.
3. Go to **Grow users > Translations > App strings**.
4. Select **Get started**.
5. Select **Add languages** and choose the target languages.
6. Select the draft bundle to preview the generated translations.
7. Review and edit translations where needed.
8. Exclude brand names or technical terms by disabling **Translate** for those keys.
9. Select **Turn on automatic translations**.

After it is enabled, future draft bundles are translated automatically from the latest `strings.xml`. New or changed strings are regenerated while unchanged strings remain consistent.

Important behavior:

- Languages selected for automatic translation are managed by Play. Existing translations for those selected languages can be overridden.
- Right-to-left languages require layout and device testing.
- Generated translations should be reviewed before production release.
- Google states that the generated app-string translations do not increase the installable APK size.

Official guide:

https://support.google.com/googleplay/android-developer/answer/9844778

## iOS: Xcode agents and String Catalog

Apple does not provide the same App Store server-side Gemini translation service. Apple's current developer workflow uses coding agents in Xcode and String Catalogs.

The canonical catalog is:

`assets/localization/Localizable.xcstrings`

It is bundled as a Flutter asset and read by the localization service. This means translations added to the catalog can be used without maintaining separate Dart translation maps.

### Xcode workflow

1. Open the iOS workspace in the current Xcode version.
2. Open `assets/localization/Localizable.xcstrings`.
3. Ask the Xcode coding agent to add the selected languages and translate the English strings.
4. Review placeholders such as `%1$d` and `%1$s`.
5. Test each locale, especially Arabic and Urdu layouts.
6. Commit the updated catalog.

The iOS bundle declares the supported languages through `CFBundleLocalizations`, so users can select a preferred language for the app in iOS Settings.

Official Apple localization overview:

https://developer.apple.com/localization/

## Adding a new string

Every new user-visible string must be added with the same key to all three sources:

1. `lib/localization/app_strings.dart` — English fallback
2. `android/app/src/main/res/values/strings.xml` — Google Play Gemini source
3. `assets/localization/Localizable.xcstrings` — iOS catalog

Do not add user-visible hardcoded text directly inside widgets.

## Placeholders

Use positional placeholders:

- `%1$d` for integer values
- `%1$s` for text values
- `%2$d`, `%2$s`, and so on for additional values

The Dart localization formatter replaces these placeholders after the localized value is loaded.
