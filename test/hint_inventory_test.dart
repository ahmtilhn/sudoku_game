import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/local_progress_store.dart';

void main() {
  group('hint inventory', () {
    test('starts with a limited balance and consumes one hint at a time', () async {
      final store = await LocalProgressStore.createInMemory();

      expect(store.hints, LocalProgressStore.initialHints);
      expect(await store.consumeHint(), isTrue);
      expect(store.hints, LocalProgressStore.initialHints - 1);

      expect(await store.consumeHint(), isTrue);
      expect(await store.consumeHint(), isTrue);
      expect(await store.consumeHint(), isFalse);
      expect(store.hints, 0);
    });

    test('buys one hint with coins as a single transaction', () async {
      final store = await LocalProgressStore.createInMemory(
        initialValues: <String, Object>{
          'career_coins_v1': 20,
          'hint_inventory_v1': 0,
        },
      );

      expect(await store.purchaseHint(coinCost: 15), isTrue);
      expect(store.coins, 5);
      expect(store.hints, 1);
      expect(await store.consumeHint(), isTrue);
      expect(store.hints, 0);
      expect(await store.purchaseHint(coinCost: 15), isFalse);
    });
  });
}
