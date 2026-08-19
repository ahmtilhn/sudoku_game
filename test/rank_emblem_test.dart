import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/rank_identity_models.dart';
import 'package:sudoku_game/widgets/rank_emblem.dart';

void main() {
  testWidgets('all 15 rank emblems render without a background container', (
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

    expect(tester.takeException(), isNull);
    expect(find.byType(RankEmblem), findsNWidgets(15));
    for (final tier in rankTierCatalog) {
      expect(find.byKey(ValueKey<String>('emblem-${tier.key}')), findsOneWidget);
    }
  });

  testWidgets('division labels are explicitly visible as roman numerals', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              RankEmblem(rankKey: 'bronze_3'),
              RankEmblem(rankKey: 'bronze_2'),
              RankEmblem(rankKey: 'bronze_1'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('III'), findsOneWidget);
    expect(find.text('II'), findsOneWidget);
    expect(find.text('I'), findsOneWidget);
  });
}
