import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/avatar_preset_catalog.dart';
import 'package:sudoku_game/models/rank_identity_models.dart';
import 'package:sudoku_game/widgets/player_avatar.dart';

void main() {
  test('competitive identity exposes 96 unique game-relevant avatar presets', () {
    expect(AvatarPresetCatalog.all, hasLength(96));
    final keys = AvatarPresetCatalog.all.map((avatar) => avatar.key).toSet();
    expect(keys, hasLength(96));
    expect(keys.firstWhere((key) => key == 'preset_001'), 'preset_001');
    expect(keys.firstWhere((key) => key == 'preset_096'), 'preset_096');
  });

  test('visible rank catalog has 15 ordered 300-RP divisions', () {
    expect(rankTierCatalog, hasLength(15));
    for (var index = 0; index < rankTierCatalog.length; index++) {
      expect(rankTierCatalog[index].minPoints, index * 300);
    }
    expect(rankTierCatalog.first.key, 'bronze_3');
    expect(rankTierCatalog.last.key, 'master_1');
  });

  test('composite identity parser limits frame decorations to three slots', () {
    final identity = RankIdentityKey.parse(
      'idv1|preset_042|platinum_1|unbeaten_shield_50,perfect_star,giant_slayer,veteran_1000',
    );
    expect(identity.avatarKey, 'preset_042');
    expect(identity.frameKey, 'platinum_1');
    expect(identity.decorationKeys, hasLength(3));
    expect(identity.decorationKeys, <String>[
      'unbeaten_shield_50',
      'perfect_star',
      'giant_slayer',
    ]);
  });

  testWidgets('avatar renders rank frame and three achievement decorations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayerAvatar(
              displayName: 'Ranked Player',
              avatarKey:
                  'idv1|preset_042|master_1|unbeaten_shield_50,perfect_crystal_star,veteran_1000',
              radius: 48,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(PlayerAvatar), findsOneWidget);
  });
}
