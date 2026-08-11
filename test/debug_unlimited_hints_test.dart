import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/local_progress_store.dart';

void main() {
  test('unlimited hint inventory never decrements', () async {
    final store = await LocalProgressStore.createInMemory(
      unlimitedHints: true,
    );
    final initial = store.hints;

    for (var index = 0; index < 20; index++) {
      expect(await store.consumeHint(), isTrue);
    }

    expect(store.unlimitedHints, isTrue);
    expect(store.hints, initial);
  });

  test('normal hint inventory still decrements', () async {
    final store = await LocalProgressStore.createInMemory(
      initialValues: <String, Object>{'hint_inventory_v1': 2},
    );

    expect(await store.consumeHint(), isTrue);
    expect(store.hints, 1);
    expect(await store.consumeHint(), isTrue);
    expect(store.hints, 0);
    expect(await store.consumeHint(), isFalse);
  });
}
