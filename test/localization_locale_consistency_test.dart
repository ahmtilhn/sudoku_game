import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime copy keeps English as the product language', () {
    final appStrings = File(
      'lib/localization/app_strings.dart',
    ).readAsStringSync();
    final uxCopy = File('lib/localization/ux_copy.dart').readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final account = File(
      'lib/features/settings/account_protection_screen.dart',
    ).readAsStringSync();

    expect(appStrings, contains("const candidates = <String>['en']"));
    expect(app, contains("locale: const Locale('en')"));
    expect(app, isNot(contains('localeResolutionCallback')));
    expect(uxCopy, isNot(contains('PlatformDispatcher.instance.locale')));
    expect(account, isNot(contains('PlatformDispatcher.instance.locale')));
    expect(account, isNot(contains('_accountText')));
  });

  test('runtime source files do not contain Turkish UI copy', () {
    final turkishCharacters = RegExp(r'[çğıöşüÇĞİÖŞÜ]');
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in libFiles) {
      final source = file.readAsStringSync();
      expect(
        turkishCharacters.hasMatch(source),
        isFalse,
        reason: '${file.path} contains Turkish runtime copy',
      );
    }
  });

  test('visible UI strings are routed through the localization catalog', () {
    final directUiString = RegExp(
      r"(Text|SelectableText)\('\w|"
      r"title: '\w|subtitle: '\w|label: '\w|tooltip: '\w|"
      r"helperText: '\w|labelText: '\w|hintText: '\w|"
      r"child: const Text\('\w|child: Text\('\w",
    );
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in libFiles) {
      final source = file.readAsStringSync();
      expect(
        directUiString.hasMatch(source),
        isFalse,
        reason: '${file.path} contains visible copy outside AppStrings',
      );
    }
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

  test('profile edit copy is available for every iOS catalog locale', () {
    final raw = File(
      'assets/localization/Localizable.xcstrings',
    ).readAsStringSync();
    final catalog = jsonDecode(raw) as Map<String, dynamic>;
    final strings = (catalog['strings'] as Map).cast<String, dynamic>();
    final expectedLocales = <String>{
      'en',
      'tr',
      'de',
      'fr',
      'es',
      'pt',
      'it',
      'nl',
      'pl',
      'ru',
      'uk',
      'ar',
      'hi',
      'id',
      'ja',
      'ko',
      'zh-Hans',
      'zh-Hant',
      'th',
      'vi',
      'bn',
      'ur',
    };

    for (final key in <String>[
      'profile_edit_preview_body',
      'profile_display_helper',
      'profile_display_error',
      'profile_search_name',
      'profile_search_helper',
      'profile_search_error',
      'profile_discovery_title',
      'profile_discovery_on',
      'profile_discovery_off',
      'pause_game',
      'pause_body',
      'restart_puzzle_title',
      'restart_puzzle_body',
      'fantasy_mode_title',
      'offline_special_mode',
      'platform_leaderboards_body',
      'platform_global_rank_body',
      'platform_difficulty_rank_body',
      'platform_achievements_body',
    ]) {
      final definition = strings[key];
      expect(definition, isA<Map>(), reason: '$key is missing');
      final localizations = ((definition as Map)['localizations'] as Map)
          .cast<String, dynamic>();
      expect(localizations.keys.toSet(), expectedLocales, reason: key);
      for (final locale in expectedLocales) {
        final unit = localizations[locale]['stringUnit'] as Map;
        expect((unit['value'] as String).trim(), isNotEmpty);
      }
    }
  });
}
