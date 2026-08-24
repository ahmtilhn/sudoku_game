import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/rank_identity_models.dart';
import 'package:sudoku_game/widgets/rank_emblem.dart';

void main() {
  test('official rank asset mapping covers all 15 competitive tiers', () {
    expect(rankEmblemAssets.length, rankTierCatalog.length);

    for (final tier in rankTierCatalog) {
      expect(rankEmblemAssets.containsKey(tier.key), isTrue);
      expect(rankAssetPath(tier.key), startsWith('assets/rank/'));
    }

    expect(rankAssetPath('platinum_3'), 'assets/rank/platinium_3.png');
    expect(rankAssetPath('platinum_2'), 'assets/rank/platinium_2.png');
    expect(rankAssetPath('platinum_1'), 'assets/rank/platinium_1.png');
    expect(rankAssetPath('unknown_rank'), 'assets/rank/bronze_3.png');
  });

  testWidgets('all 15 rank emblems render from the official asset set', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final tier in rankTierCatalog)
                RankEmblem(
                  key: ValueKey<String>('emblem-${tier.key}'),
                  rankKey: tier.key,
                  size: 72,
                ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(RankEmblem), findsNWidgets(15));
    expect(find.byType(Image), findsNWidgets(15));

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(rankTierCatalog.length));

    for (var index = 0; index < rankTierCatalog.length; index++) {
      final provider = images[index].image;
      expect(provider, isA<AssetImage>());
      expect(
        (provider as AssetImage).assetName,
        rankAssetPath(rankTierCatalog[index].key),
      );
    }
  });
}
