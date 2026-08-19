import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/avatar_preset_catalog.dart';
import 'package:sudoku_game/models/rank_identity_models.dart';

void main() {
  group('rank identity catalog', () {
    test('contains all 15 agreed visible divisions', () {
      expect(rankTierCatalog, hasLength(15));
      expect(rankTierForPoints(0).label, 'Bronze III');
      expect(rankTierForPoints(299).label, 'Bronze III');
      expect(rankTierForPoints(300).label, 'Bronze II');
      expect(rankTierForPoints(600).label, 'Bronze I');
      expect(rankTierForPoints(900).label, 'Silver III');
      expect(rankTierForPoints(1800).label, 'Gold III');
      expect(rankTierForPoints(2700).label, 'Platinum III');
      expect(rankTierForPoints(3600).label, 'Master III');
      expect(rankTierForPoints(3900).label, 'Master II');
      expect(rankTierForPoints(4200).label, 'Master I');
      expect(rankTierForPoints(999999).label, 'Master I');
    });

    test('keeps every pre-Master-I division exactly 300 RP wide', () {
      for (var index = 0; index < rankTierCatalog.length - 1; index++) {
        expect(
          rankTierCatalog[index + 1].minPoints -
              rankTierCatalog[index].minPoints,
          300,
          reason: rankTierCatalog[index].label,
        );
      }
    });

    test('identity key round-trips avatar frame and at most three badges', () {
      final encoded = RankIdentityKey(
        avatarKey: 'preset_040',
        frameKey: 'gold_1',
        decorationKeys: const <String>[
          'unbeaten_shield_50',
          'perfect_star',
          'giant_slayer',
          'must_be_dropped',
        ],
      ).encode();

      final parsed = RankIdentityKey.parse(encoded);
      expect(parsed.avatarKey, 'preset_040');
      expect(parsed.frameKey, 'gold_1');
      expect(parsed.decorationKeys, <String>[
        'unbeaten_shield_50',
        'perfect_star',
        'giant_slayer',
      ]);
    });

    test('legacy identity parsing remains readable before UI normalization', () {
      final parsed = RankIdentityKey.parse('home-profile-platform');
      expect(parsed.avatarKey, 'home-profile-platform');
      expect(parsed.frameKey, isNull);
      expect(parsed.decorationKeys, isEmpty);
      expect(
        AvatarPresetCatalog.normalizeKey(parsed.avatarKey),
        AvatarPresetCatalog.firstKey,
      );
    });
  });

  group('bundled avatar catalog', () {
    test('contains exactly the current 40 assets with stable profile keys', () {
      expect(AvatarPresetCatalog.all, hasLength(40));
      expect(AvatarPresetCatalog.all.first.key, 'preset_001');
      expect(AvatarPresetCatalog.all.last.key, 'preset_040');
      expect(
        AvatarPresetCatalog.all.map((item) => item.key).toSet(),
        hasLength(40),
      );
      expect(
        AvatarPresetCatalog.all.every(
          (item) => item.assetPath.startsWith('assets/avatar/'),
        ),
        isTrue,
      );
    });

    test('lookup rejects malformed or out-of-range preset keys', () {
      expect(AvatarPresetCatalog.byKey('preset_001'), isNotNull);
      expect(AvatarPresetCatalog.byKey('preset_040'), isNotNull);
      expect(AvatarPresetCatalog.byKey('preset_000'), isNull);
      expect(AvatarPresetCatalog.byKey('preset_041'), isNull);
      expect(AvatarPresetCatalog.byKey('preset_096'), isNull);
      expect(AvatarPresetCatalog.byKey('random-photo'), isNull);
    });
  });
}
