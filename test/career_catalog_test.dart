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
      final chapterLevels = CareerCatalog.levels
          .where((level) => level.chapter == chapter)
          .toList();
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

  test('career continues with numbered procedural levels after fifty', () {
    final fifty = CareerCatalog.levelAt(50);
    final fiftyOne = CareerCatalog.levelAt(51);
    final fiftyTwo = CareerCatalog.levelAt(52);

    expect(fifty.id, 'career-050');
    expect(fifty.isEndless, isFalse);
    expect(fiftyOne.id, 'career-051');
    expect(fiftyOne.number, 51);
    expect(fiftyOne.isEndless, isTrue);
    expect(fiftyTwo.id, 'career-052');
    expect(fiftyTwo.number, 52);
    expect(fiftyTwo.isEndless, isTrue);
    expect(fiftyTwo.seed, isNot(fiftyOne.seed));
  });

  test('procedural career puzzles are stable and distinct by level', () {
    final level51 = CareerCatalog.levelAt(51);
    final level52 = CareerCatalog.levelAt(52);
    final first51 = CareerCatalog.puzzleFor(level51);
    final repeated51 = CareerCatalog.puzzleFor(level51);
    final puzzle52 = CareerCatalog.puzzleFor(level52);

    expect(identical(first51, repeated51), isTrue);
    expect(first51.id, 'career-051');
    expect(puzzle52.id, 'career-052');
    expect(first51.solution, isNot(puzzle52.solution));
    expect(SudokuEngine.hasUniqueSolution(first51), isTrue);
    expect(SudokuEngine.hasUniqueSolution(puzzle52), isTrue);
  });

  test('career numbering has no maximum or three-digit wraparound', () {
    final level1000 = CareerCatalog.levelAt(1000);
    final level1001 = CareerCatalog.levelAt(1001);

    expect(level1000.id, 'career-1000');
    expect(level1001.id, 'career-1001');
    expect(CareerCatalog.byId(level1001.id)?.number, 1001);
    expect(CareerCatalog.previousOf(level1001)?.number, 1000);
  });
}
