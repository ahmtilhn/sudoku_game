import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/localization/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppStrings keys are present in every string catalog locale', () async {
    final source = await rootBundle.loadString(
      'assets/localization/Localizable.xcstrings',
    );
    final catalog = jsonDecode(source) as Map<String, dynamic>;
    final strings = catalog['strings'] as Map<String, dynamic>;
    final expectedLocales = <String>{
      for (final entry in strings.values)
        if (entry is Map && entry['localizations'] is Map)
          ...(entry['localizations'] as Map).keys.cast<String>(),
    };

    final missing = <String>[];
    final missingLocale = <String>[];
    for (final key in AppStrings.english.keys) {
      final entry = strings[key] as Map<String, dynamic>?;
      if (entry == null) {
        missing.add(key);
        continue;
      }
      final localizations = entry['localizations'] as Map<String, dynamic>?;
      for (final locale in expectedLocales) {
        final localization = localizations?[locale] as Map<String, dynamic>?;
        final unit = localization?['stringUnit'] as Map<String, dynamic>?;
        final value = unit?['value'];
        if (value is! String || value.trim().isEmpty) {
          missingLocale.add('$key:$locale');
        }
      }
    }

    expect(missing, isEmpty, reason: 'Missing catalog keys');
    expect(missingLocale, isEmpty, reason: 'Missing catalog locale values');
  });

  test('test strings do not depend on platform localization channels', () {
    final strings = AppStrings.forTesting();
    expect(strings.text('find_new_match'), 'Find new match');
    expect(strings.text('coin_amount', const <Object>[100]), '100 Coin');
  });
}
