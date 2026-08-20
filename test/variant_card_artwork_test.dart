import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('9x9 and 16x16 card artwork is registered and present', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = File('lib/widgets/duel_asset_icon.dart').readAsStringSync();

    expect(pubspec, contains('- assets/cards/'));
    expect(File('assets/cards/9x9.png').existsSync(), isTrue);
    expect(File('assets/cards/16x16.png').existsSync(), isTrue);
    expect(assets, contains("board9Pro = 'assets/cards/9x9.png'"));
    expect(assets, contains("board16Pro = 'assets/cards/16x16.png'"));
    expect(assets, contains('board9Pro,'));
    expect(assets, contains('board16Pro,'));
  });

  test('all variant selection card surfaces use centralized artwork', () {
    final surfaces = <String, String>{
      'quick play': 'lib/features/home/professional_home_screen.dart',
      'career': 'lib/features/career/career_hub_screen.dart',
      'matchmaking': 'lib/features/duel/matchmaking_screen.dart',
    };

    for (final entry in surfaces.entries) {
      final source = File(entry.value).readAsStringSync();
      expect(
        source,
        contains('DuelAsset.board9Pro'),
        reason: '${entry.key} must use the centralized 9x9 card artwork',
      );
      expect(
        source,
        contains('DuelAsset.board16Pro'),
        reason: '${entry.key} must use the centralized 16x16 card artwork',
      );
    }
  });
}
