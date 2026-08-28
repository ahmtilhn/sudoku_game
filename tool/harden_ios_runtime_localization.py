#!/usr/bin/env python3
"""Make iOS locale selection deterministic without changing Android behavior."""

from pathlib import Path
import re

APP_STRINGS = Path("lib/localization/app_strings.dart")
APP_DELEGATE = Path("ios/Runner/AppDelegate.swift")


def patch_app_strings() -> None:
    source = APP_STRINGS.read_text(encoding="utf-8")
    replacement = r'''  static Future<AppStrings> load() async {
    final values = Map<String, String>.from(english);
    final catalogLocales = defaultTargetPlatform == TargetPlatform.iOS
        ? await _preferredIosLocales()
        : const <Locale>[Locale('en')];
    await _loadStringCatalog(values, catalogLocales);

    // Google Play can provide Android resource translations at runtime.
    // iOS uses only the bundled String Catalog after locale resolution so a
    // native English resource can never overwrite the selected iOS language.
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final response = await _channel.invokeMethod<Map<Object?, Object?>>(
          'getStrings',
          <String, Object>{'keys': english.keys.toList(growable: false)},
        );
        if (response != null) {
          for (final entry in response.entries) {
            final key = entry.key;
            final value = entry.value;
            if (key is String &&
                value is String &&
                value.isNotEmpty &&
                value != key) {
              values[key] = value;
            }
          }
        }
      } on MissingPluginException {
        // Tests and unsupported platforms use catalog/English fallback.
      } on PlatformException {
        // Localization failure must never block startup.
      }
    }
    return AppStrings._(values);
  }

  static Future<List<Locale>> _preferredIosLocales() async {
    final flutterLocales = PlatformDispatcher.instance.locales;
    try {
      final preferredLanguages = await _channel.invokeListMethod<String>(
        'getPreferredLocales',
      );
      if (preferredLanguages != null && preferredLanguages.isNotEmpty) {
        final nativeLocales = preferredLanguages
            .map(_localeFromLanguageTag)
            .whereType<Locale>()
            .toList(growable: false);
        if (nativeLocales.isNotEmpty) {
          return <Locale>[...nativeLocales, ...flutterLocales];
        }
      }
    } on MissingPluginException {
      // Fall through to Flutter's platform locales.
    } on PlatformException {
      // Fall through to Flutter's platform locales.
    }
    return flutterLocales.isNotEmpty
        ? flutterLocales
        : const <Locale>[Locale('en')];
  }

  static Locale? _localeFromLanguageTag(String rawTag) {
    final tag = rawTag.trim().replaceAll('_', '-');
    if (tag.isEmpty) return null;
    final parts = tag
        .split('-')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return null;

    final language = parts.first.toLowerCase();
    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (part.length == 4 && script == null) {
        script = '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      } else if ((part.length == 2 || part.length == 3) && country == null) {
        country = part.toUpperCase();
      }
    }
    return Locale.fromSubtags(
      languageCode: language,
      scriptCode: script,
      countryCode: country,
    );
  }

  static Future<void> _loadStringCatalog('''

    pattern = re.compile(
        r"  static Future<AppStrings> load\(\) async \{.*?\n  static Future<void> _loadStringCatalog\(",
        re.S,
    )
    updated, count = pattern.subn(replacement, source, count=1)
    if count != 1:
        raise SystemExit("Could not patch AppStrings.load exactly once")
    APP_STRINGS.write_text(updated, encoding="utf-8")


def patch_app_delegate() -> None:
    source = APP_DELEGATE.read_text(encoding="utf-8")
    replacement = r'''  private func configureLocalizationChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.devovia.sudoku/localization",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getPreferredLocales":
        result(Locale.preferredLanguages)
      case "getStrings":
        // Flutter's String Catalog is the single iOS source of app copy.
        result([String: String]())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    localizationChannel = channel
  }

  private func configureGameServicesChannel'''

    pattern = re.compile(
        r"  private func configureLocalizationChannel\(messenger: FlutterBinaryMessenger\) \{.*?\n  private func configureGameServicesChannel",
        re.S,
    )
    updated, count = pattern.subn(replacement, source, count=1)
    if count != 1:
        raise SystemExit("Could not patch iOS localization bridge exactly once")
    APP_DELEGATE.write_text(updated, encoding="utf-8")


def main() -> None:
    patch_app_strings()
    patch_app_delegate()
    print("iOS runtime localization hardened")


if __name__ == "__main__":
    main()
