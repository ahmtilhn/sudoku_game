import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/country_catalog.dart';

void main() {
  test('ISO country codes render flag emoji without abbreviations', () {
    expect(countryFlagEmoji('NL'), '🇳🇱');
    expect(countryFlagEmoji('tr'), '🇹🇷');
    expect(countryFlagEmoji('US'), '🇺🇸');
    expect(countryFlagEmoji(null), isEmpty);
    expect(countryFlagEmoji('NLD'), isEmpty);
  });

  test('country catalog resolves selectable countries by ISO code', () {
    expect(countryOptionForCode('NL')?.name, 'Netherlands');
    expect(countryOptionForCode('TR')?.name, 'Türkiye');
    expect(countryOptionForCode('DE')?.flag, '🇩🇪');
    expect(countryOptions.length, greaterThanOrEqualTo(240));
  });
}
