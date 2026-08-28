#!/usr/bin/env python3
"""Enable iOS runtime localization and keep Android app-string source complete.

This migration is intentionally narrow and idempotent so it can safely run on
main while other agents are changing unrelated UI files.
"""

from __future__ import annotations

import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "lib" / "app.dart"
APP_STRINGS = ROOT / "lib" / "localization" / "app_strings.dart"
IOS_CATALOG = ROOT / "assets" / "localization" / "Localizable.xcstrings"
ANDROID_STRINGS = ROOT / "android" / "app" / "src" / "main" / "res" / "values" / "strings.xml"
LOCALE_TEST = ROOT / "test" / "localization_locale_consistency_test.dart"


def write_if_changed(path: Path, value: str) -> bool:
    previous = path.read_text(encoding="utf-8")
    if previous == value:
        return False
    path.write_text(value, encoding="utf-8")
    return True


def enable_material_app_locale_resolution() -> bool:
    source = APP.read_text(encoding="utf-8")
    pinned = "            locale: const Locale('en'),\n"
    if pinned in source:
        source = source.replace(pinned, "", 1)
    if "locale: const Locale('en')" in source:
        raise RuntimeError("A second English locale pin is still present in lib/app.dart")
    if "supportedLocales: AppStrings.supportedLocales" not in source:
        raise RuntimeError("MaterialApp supportedLocales wiring is missing")
    return write_if_changed(APP, source)


def enable_catalog_locale_resolution() -> bool:
    source = APP_STRINGS.read_text(encoding="utf-8")

    if "import 'dart:ui' show PlatformDispatcher;" not in source:
        source = source.replace(
            "import 'dart:convert';\n",
            "import 'dart:convert';\nimport 'dart:ui' show PlatformDispatcher;\n",
            1,
        )

    if "package:flutter/foundation.dart" not in source:
        source = source.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;\n"
            "import 'package:flutter/material.dart';\n",
            1,
        )

    old_load = """    await _loadStringCatalog(values);\n    try {\n"""
    new_load = """    final catalogLocales = defaultTargetPlatform == TargetPlatform.iOS\n        ? PlatformDispatcher.instance.locales\n        : const <Locale>[Locale('en')];\n    await _loadStringCatalog(values, catalogLocales);\n    try {\n"""
    if old_load in source:
        source = source.replace(old_load, new_load, 1)
    elif new_load not in source:
        raise RuntimeError("Could not find AppStrings.load catalog bootstrap")

    old_signature = "  static Future<void> _loadStringCatalog(Map<String, String> values) async {"
    new_signature = """  static Future<void> _loadStringCatalog(\n    Map<String, String> values,\n    List<Locale> preferredLocales,\n  ) async {"""
    if old_signature in source:
        source = source.replace(old_signature, new_signature, 1)
    elif new_signature not in source:
        raise RuntimeError("Could not find _loadStringCatalog signature")

    english_only = """      // Sudoku Duel currently ships with English as the product language.\n      // The catalog still stores platform translations, but in-app copy must\n      // not switch to a device language unless a real language selector is\n      // added and persisted.\n      const candidates = <String>['en'];\n"""
    locale_aware = """      final candidates = _catalogLocaleCandidates(preferredLocales);\n"""
    if english_only in source:
        source = source.replace(english_only, locale_aware, 1)
    elif locale_aware not in source:
        raise RuntimeError("Could not find the English-only catalog candidate block")

    helper = r"""
  static List<String> _catalogLocaleCandidates(List<Locale> preferredLocales) {
    final candidates = <String>[];

    void add(String candidate) {
      if (candidate.isNotEmpty && !candidates.contains(candidate)) {
        candidates.add(candidate);
      }
    }

    for (final locale in preferredLocales) {
      final language = locale.languageCode.toLowerCase();
      final script = locale.scriptCode;
      final country = locale.countryCode?.toUpperCase();

      if (language == 'zh') {
        if (script == 'Hant' ||
            const <String>{'TW', 'HK', 'MO'}.contains(country)) {
          add('zh-Hant');
        } else if (script == 'Hans' ||
            const <String>{'CN', 'SG'}.contains(country)) {
          add('zh-Hans');
        }
      }

      if (script != null && script.isNotEmpty) {
        add('$language-$script');
      }
      if (country != null && country.isNotEmpty) {
        add('$language-$country');
      }
      add(language);
    }

    add('en');
    return candidates;
  }

"""
    marker = "  String text(String key, [List<Object> arguments = const <Object>[]]) {"
    if "static List<String> _catalogLocaleCandidates" not in source:
        if marker not in source:
            raise RuntimeError("Could not find AppStrings.text insertion point")
        source = source.replace(marker, helper + marker, 1)

    if "const candidates = <String>['en']" in source:
        raise RuntimeError("English-only iOS catalog selection is still present")

    return write_if_changed(APP_STRINGS, source)


def update_locale_regression_test() -> bool:
    source = LOCALE_TEST.read_text(encoding="utf-8")
    pattern = re.compile(
        r"  test\('runtime copy keeps English as the product language', \(\) \{.*?\n  \}\);\n",
        re.DOTALL,
    )
    replacement = """  test('runtime localization follows the platform locale', () {\n    final appStrings = File(\n      'lib/localization/app_strings.dart',\n    ).readAsStringSync();\n    final app = File('lib/app.dart').readAsStringSync();\n\n    expect(appStrings, contains('PlatformDispatcher.instance.locales'));\n    expect(appStrings, contains('defaultTargetPlatform == TargetPlatform.iOS'));\n    expect(appStrings, contains('_catalogLocaleCandidates(preferredLocales)'));\n    expect(appStrings, contains(\"add('en');\"));\n    expect(appStrings, isNot(contains(\"const candidates = <String>['en']\")));\n    expect(app, isNot(contains(\"locale: const Locale('en')\")));\n    expect(app, contains('supportedLocales: AppStrings.supportedLocales'));\n  });\n"""
    if pattern.search(source):
        source = pattern.sub(replacement, source, count=1)
    elif "runtime localization follows the platform locale" not in source:
        raise RuntimeError("Could not find the old English-only localization regression test")
    return write_if_changed(LOCALE_TEST, source)


def android_resource_value(value: str) -> str:
    value = value.replace("\\", "\\\\")
    value = value.replace("\n", "\\n")
    value = value.replace("'", "\\'")
    value = value.replace('"', '\\"')
    if value.startswith("@") or value.startswith("?"):
        value = "\\" + value
    return html.escape(value, quote=False)


def sync_android_app_strings() -> tuple[bool, int]:
    catalog = json.loads(IOS_CATALOG.read_text(encoding="utf-8"))
    catalog_strings = catalog.get("strings", {})
    source = ANDROID_STRINGS.read_text(encoding="utf-8")
    existing = set(re.findall(r'<string\s+name="([^"]+)"', source))

    missing: list[tuple[str, str]] = []
    for key in sorted(catalog_strings):
        if key in existing:
            continue
        definition = catalog_strings[key]
        if not isinstance(definition, dict):
            continue
        localizations = definition.get("localizations")
        if not isinstance(localizations, dict):
            continue
        english = localizations.get("en")
        if not isinstance(english, dict):
            continue
        unit = english.get("stringUnit")
        if not isinstance(unit, dict):
            continue
        value = unit.get("value")
        if isinstance(value, str) and value.strip():
            missing.append((key, value))

    if not missing:
        return False, 0

    close = "</resources>"
    if close not in source:
        raise RuntimeError("android strings.xml is missing </resources>")

    lines = [
        "    <!-- Auto-synchronized AppStrings keys for Google Play app-string translation. -->\n"
    ]
    for key, value in missing:
        escaped = android_resource_value(value)
        lines.append(
            f'    <string name="{key}" formatted="false">{escaped}</string>\n'
        )
    source = source.replace(close, "".join(lines) + close, 1)
    return write_if_changed(ANDROID_STRINGS, source), len(missing)


def main() -> int:
    changed: list[str] = []
    if enable_material_app_locale_resolution():
        changed.append(str(APP.relative_to(ROOT)))
    if enable_catalog_locale_resolution():
        changed.append(str(APP_STRINGS.relative_to(ROOT)))
    if update_locale_regression_test():
        changed.append(str(LOCALE_TEST.relative_to(ROOT)))
    android_changed, missing_count = sync_android_app_strings()
    if android_changed:
        changed.append(str(ANDROID_STRINGS.relative_to(ROOT)))

    print(
        "iOS runtime localization enabled; "
        f"Android source gained {missing_count} missing catalog keys."
    )
    if changed:
        print("Changed files:")
        for path in changed:
            print(f"- {path}")
    else:
        print("No changes required; localization runtime is already synchronized.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
