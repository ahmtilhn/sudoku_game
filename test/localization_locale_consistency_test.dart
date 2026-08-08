import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy bilingual copy follows the same platform locale as AppStrings', () {
    final appStrings = File(
      'lib/localization/app_strings.dart',
    ).readAsStringSync();
    final uxCopy = File('lib/localization/ux_copy.dart').readAsStringSync();
    final account = File(
      'lib/features/settings/account_protection_screen.dart',
    ).readAsStringSync();

    expect(appStrings, contains('PlatformDispatcher.instance.locale'));
    expect(
      uxCopy,
      contains('PlatformDispatcher.instance.locale.languageCode'),
    );
    expect(
      account,
      contains('PlatformDispatcher.instance.locale.languageCode'),
    );
    expect(
      uxCopy,
      isNot(contains('Localizations.localeOf(context).languageCode')),
    );
    expect(
      account,
      isNot(contains('Localizations.localeOf(context).languageCode')),
    );
  });

  test('English localization catalog does not contain Turkish UI copy', () {
    final raw = File(
      'assets/localization/Localizable.xcstrings',
    ).readAsStringSync();
    final catalog = jsonDecode(raw) as Map<String, dynamic>;
    final strings = (catalog['strings'] as Map).cast<String, dynamic>();
    final turkishCharacters = RegExp(r'[çğıöşüÇĞİÖŞÜ]');

    for (final entry in strings.entries) {
      final definition = entry.value;
      if (definition is! Map) continue;
      final localizations = definition['localizations'];
      if (localizations is! Map) continue;
      final english = localizations['en'];
      if (english is! Map) continue;
      final unit = english['stringUnit'];
      if (unit is! Map) continue;
      final value = unit['value'];
      if (value is String) {
        expect(
          turkishCharacters.hasMatch(value),
          isFalse,
          reason:
              'English localization ${entry.key} contains Turkish text: $value',
        );
      }
    }
  });
}
