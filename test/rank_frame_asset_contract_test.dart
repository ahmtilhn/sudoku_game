import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/rank_frame_asset_catalog.dart';

void main() {
  const expected = <String, String>{
    'bronze_3': 'assets/frames/bronz_3.png',
    'bronze_2': 'assets/frames/bronze_2.png',
    'bronze_1': 'assets/frames/bronze_1.png',
    'silver_3': 'assets/frames/silver_3.png',
    'silver_2': 'assets/frames/silver_2.png',
    'silver_1': 'assets/frames/silver_1.png',
    'gold_3': 'assets/frames/gold_3.png',
    'gold_2': 'assets/frames/gold_2.png',
    'gold_1': 'assets/frames/gold_1.png',
    'platinum_3': 'assets/frames/platinum_3.png',
    'platinum_2': 'assets/frames/platinum_2.png',
    'platinum_1': 'assets/frames/platinum_1.png',
    'master_3': 'assets/frames/master_3.png',
    'master_2': 'assets/frames/master_2.png',
    'master_1': 'assets/frames/master_1.png',
  };

  test('all 15 ranked divisions map to the pushed frame PNGs', () {
    expect(RankFrameAssetCatalog.keys, hasLength(15));
    expect(RankFrameAssetCatalog.keys.toSet(), expected.keys.toSet());

    for (final entry in expected.entries) {
      expect(
        RankFrameAssetCatalog.assetPathForKey(entry.key),
        entry.value,
        reason: 'Wrong frame mapping for ${entry.key}',
      );
      expect(
        File(entry.value).existsSync(),
        isTrue,
        reason: 'Missing frame asset ${entry.value}',
      );
    }
  });

  test('Bronze III keeps the current bronz_3 filename safely mapped', () {
    expect(
      RankFrameAssetCatalog.assetPathForKey('bronze_3'),
      'assets/frames/bronz_3.png',
    );
    expect(RankFrameAssetCatalog.normalizeKey('unknown'), 'bronze_3');
  });

  test('rank frame renderer uses assets as its only frame visual source', () {
    final source = File('lib/widgets/rank_frame_overlay.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(source, contains('RankFrameAssetCatalog.assetPathForKey'));
    expect(source, contains('Image.asset('));
    expect(source, isNot(contains('_RankFrameVisual')));
    expect(source, isNot(contains('SweepGradient')));
    expect(source, isNot(contains('_DivisionMedallion')));
    expect(source, isNot(contains('_Winglet')));
    expect(pubspec, contains('- assets/frames/'));
  });
}
