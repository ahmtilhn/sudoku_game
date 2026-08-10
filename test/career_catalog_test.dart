import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/career_catalog.dart';
import 'package:sudoku_game/domain/sudoku.dart';

void main() {
  test('career contains fifty unique, ordered designed levels', () {
    final levels = CareerCatalog.levels;

    expect(levels, hasLength(50));
    expect(levels.map((level) => level.id).toSet(), hasLength(50));
    expect(levels.first.id, 'career-001');
    expect(levels.last.id, 'career-050');
    expect(
      levels.map((level) => level.number),
      orderedEquals(List<int>.generate(50, (index) => index + 1)),
    );
  });

  test('designed career has ten levels per difficulty chapter', () {
    for (var chapter = 1; chapter <= 5; chapter++) {
      final chapterLevels = CareerCatalog.chapterLevels(chapter);
      expect(chapterLevels, hasLength(10));
      expect(
        chapterLevels.every(
          (level) => level.difficulty == SudokuDifficulty.values[chapter - 1],
        ),
        isTrue,
      );
      expect(chapterLevels.first.isChapterStart, isTrue);
    }
  });

  test('first five levels teach four by four before nine by nine', () {
    expect(
      CareerCatalog.levels.take(5).every((level) => level.size == 4),
      isTrue,
    );
    expect(
      CareerCatalog.levels.skip(5).every((level) => level.size == 9),
      isTrue,
    );
  });

  test('level puzzle identity is stable and matches the level', () {
    final level = CareerCatalog.levels.first;
    final first = CareerCatalog.puzzleFor(level);
    final repeated = CareerCatalog.puzzleFor(level);

    expect(first.id, level.id);
    expect(identical(first, repeated), isTrue);
    expect(first.size, level.size);
    expect(first.difficulty, level.difficulty);
    expect(first.puzzle, hasLength(first.cellCount));
    expect(first.solution, hasLength(first.cellCount));
  });

  test('previous and next level helpers preserve career order', () {
    final first = CareerCatalog.levels.first;
    final second = CareerCatalog.levels[1];
    final last = CareerCatalog.levels.last;

    expect(CareerCatalog.previousOf(first), isNull);
    expect(CareerCatalog.nextOf(first)?.id, second.id);
    expect(CareerCatalog.previousOf(second)?.id, first.id);
    expect(CareerCatalog.nextOf(last), isNull);
  });

  test('only the first incomplete level after completed progress is playable', () {
    final completed = <String>{
      CareerCatalog.levels[0].id,
      CareerCatalog.levels[1].id,
      CareerCatalog.levels[2].id,
    };
    bool isCompleted(String id) => completed.contains(id);

    expect(
      CareerCatalog.isUnlocked(CareerCatalog.levels[0], isCompleted),
      isTrue,
    );
    expect(
      CareerCatalog.isUnlocked(CareerCatalog.levels[3], isCompleted),
      isTrue,
    );
    expect(
      CareerCatalog.isUnlocked(CareerCatalog.levels[4], isCompleted),
      isFalse,
    );
    expect(CareerCatalog.firstPlayable(isCompleted)?.number, 4);
  });

  test('first playable is null when every career level is complete', () {
    expect(CareerCatalog.firstPlayable((_) => true), isNull);
  });
}
