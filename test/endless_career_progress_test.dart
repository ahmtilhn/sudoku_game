import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/career_catalog.dart';
import 'package:sudoku_game/data/local_progress_store.dart';

void main() {
  test('career unlocks level 51 after the designed fifty levels', () async {
    final store = await LocalProgressStore.createInMemory();

    expect(store.nextCareerLevelNumber, 1);
    expect(store.isCareerLevelUnlocked(1), isTrue);
    expect(store.isCareerLevelUnlocked(2), isFalse);

    for (var number = 1; number <= 50; number++) {
      final level = CareerCatalog.levelAt(number);
      expect(store.isCareerLevelUnlocked(number), isTrue);
      await store.recordResult(
        puzzleId: level.id,
        seconds: 120 + number,
        mistakes: 0,
        hints: 0,
      );
    }

    expect(store.completedCareerLevelCount, 50);
    expect(store.nextCareerLevelNumber, 51);
    expect(store.isCareerLevelUnlocked(51), isTrue);
    expect(store.isCareerLevelUnlocked(52), isFalse);
  });

  test('career continues from 51 to 52 without an upper limit', () async {
    final store = await LocalProgressStore.createInMemory();

    for (var number = 1; number <= 51; number++) {
      await store.recordResult(
        puzzleId: CareerCatalog.idForLevel(number),
        seconds: 180,
        mistakes: 1,
        hints: 0,
      );
    }

    expect(store.completedCareerLevelCount, 51);
    expect(store.nextCareerLevelNumber, 52);
    expect(store.progressForCareerLevel(51), isNotNull);
    expect(store.isCareerLevelUnlocked(52), isTrue);
  });

  test('random practice results do not advance numbered career', () async {
    final store = await LocalProgressStore.createInMemory();

    await store.recordResult(
      puzzleId: 'career-expert',
      seconds: 90,
      mistakes: 0,
      hints: 0,
    );

    expect(store.completedLevelCount, 1);
    expect(store.completedCareerLevelCount, 0);
    expect(store.nextCareerLevelNumber, 1);
  });
}
