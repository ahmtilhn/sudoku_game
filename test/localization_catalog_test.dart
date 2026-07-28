import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/localization/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('English fallback keys are present in the string catalog', () async {
    final source = await rootBundle.loadString(
      'assets/localization/Localizable.xcstrings',
    );
    final catalog = jsonDecode(source) as Map<String, dynamic>;
    final strings = catalog['strings'] as Map<String, dynamic>;

    final missing = <String>[];
    final missingEnglish = <String>[];
    for (final key in AppStrings.english.keys) {
      final entry = strings[key] as Map<String, dynamic>?;
      if (entry == null) {
        missing.add(key);
        continue;
      }
      final localizations = entry['localizations'] as Map<String, dynamic>?;
      final english = localizations?['en'] as Map<String, dynamic>?;
      final unit = english?['stringUnit'] as Map<String, dynamic>?;
      final value = unit?['value'];
      if (value is! String || value.isEmpty) {
        missingEnglish.add(key);
      }
    }

    expect(missing, isEmpty, reason: 'Missing catalog keys');
    expect(missingEnglish, isEmpty, reason: 'Missing English catalog values');
  });

  test('test strings do not depend on platform localization channels', () {
    final strings = AppStrings.forTesting();
    expect(strings.text('find_new_match'), 'Find new match');
    expect(strings.text('coin_amount', const <Object>[100]), '100 Coin');
  });
}
