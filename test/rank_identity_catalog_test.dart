import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/avatar_preset_catalog.dart';
import 'package:sudoku_game/models/rank_identity_models.dart';
import 'package:sudoku_game/widgets/player_avatar.dart';

void main() {
  test('competitive identity exposes only the 40 bundled avatar images', () {
    expect(AvatarPresetCatalog.all, hasLength(40));
    final keys = AvatarPresetCatalog.all.map((avatar) => avatar.key).toSet();
    final paths = AvatarPresetCatalog.all
        .map((avatar) => avatar.assetPath)
        .toSet();

    expect(keys, hasLength(40));
    expect(paths, hasLength(40));
    expect(AvatarPresetCatalog.all.first.key, 'preset_001');
    expect(AvatarPresetCatalog.all.last.key, 'preset_040');
    expect(AvatarPresetCatalog.all.first.assetPath, 'assets/avatar/avatar.png');
    expect(
      AvatarPresetCatalog.all.last.assetPath,
      'assets/avatar/avatar (40).png',
    );
    expect(
      AvatarPresetCatalog.all.every(
        (avatar) => avatar.assetPath.startsWith('assets/avatar/'),
      ),
      isTrue,
    );
  });

  test('legacy non-asset avatar keys collapse to the first bundled avatar', () {
    expect(AvatarPresetCatalog.normalizeKey('default'), 'preset_001');
    expect(
      AvatarPresetCatalog.normalizeKey('home-profile-platform'),
      'preset_001',
    );
    expect(AvatarPresetCatalog.normalizeKey('preset_096'), 'preset_001');
    expect(
      AvatarPresetCatalog.assetPathForKey('home-profile-platform'),
      'assets/avatar/avatar.png',
    );
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
      'idv1|preset_040|platinum_1|unbeaten_shield_50,perfect_star,giant_slayer,veteran_1000',
    );
    expect(identity.avatarKey, 'preset_040');
    expect(identity.frameKey, 'platinum_1');
    expect(identity.decorationKeys, hasLength(3));
    expect(identity.decorationKeys, <String>[
      'unbeaten_shield_50',
      'perfect_star',
      'giant_slayer',
    ]);
  });

  testWidgets('avatar renders bundled image with rank frame decorations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayerAvatar(
              displayName: 'Ranked Player',
              avatarKey:
                  'idv1|preset_040|master_1|unbeaten_shield_50,perfect_crystal_star,veteran_1000',
              radius: 48,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(PlayerAvatar), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
