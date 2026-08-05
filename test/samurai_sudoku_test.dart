import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/domain/samurai_sudoku.dart';
import 'package:sudoku_game/domain/sudoku.dart';

void main() {
  group('SamuraiTopology', () {
    test('uses a 21x21 canvas with 369 active and 36 overlap cells', () {
      expect(SamuraiTopology.canvasCellCount, 441);
      expect(SamuraiTopology.activeIndexes, hasLength(369));
      expect(
        SamuraiTopology.activeIndexes
            .where(SamuraiTopology.isOverlapIndex),
        hasLength(36),
      );
      expect(
        SamuraiTopology.canvasCellCount -
            SamuraiTopology.activeIndexes.length,
        72,
      );
    });

    test('contains all row column and box units for five boards', () {
      expect(SamuraiTopology.units, hasLength(135));
      expect(
        SamuraiTopology.units.every((unit) => unit.length == 9),
        isTrue,
      );

      final ordinary = SamuraiTopology.indexOf(0, 0);
      final overlap = SamuraiTopology.indexOf(6, 6);
      expect(SamuraiTopology.unitsByCell[ordinary], hasLength(3));
      expect(SamuraiTopology.unitsByCell[overlap], hasLength(6));
    });
  });

  group('SamuraiEngine', () {
    test('generates a valid uniquely solvable Samurai puzzle', () {
      final puzzle = SamuraiEngine.generate(
        difficulty: SudokuDifficulty.beginner,
        seed: 4101,
      );

      expect(SamuraiEngine.isPuzzleShapeValid(puzzle), isTrue);
      expect(SamuraiEngine.isSolvedBoardValid(puzzle.solution), isTrue);
      expect(SamuraiEngine.hasUniqueSolution(puzzle), isTrue);
      expect(puzzle.clueCount, lessThan(369));

      for (var index = 0; index < SamuraiTopology.canvasCellCount; index++) {
        if (!SamuraiTopology.isActiveIndex(index)) {
          expect(puzzle.puzzle[index], SamuraiTopology.inactiveCell);
          expect(puzzle.solution[index], SamuraiTopology.inactiveCell);
        }
      }
    });

    test('the same seed produces the same shared five-board puzzle', () {
      final first = SamuraiEngine.generate(
        difficulty: SudokuDifficulty.beginner,
        seed: 99123,
      );
      final second = SamuraiEngine.generate(
        difficulty: SudokuDifficulty.beginner,
        seed: 99123,
      );

      expect(second.puzzle, equals(first.puzzle));
      expect(second.solution, equals(first.solution));
    });

    test('overlap cells obey the rules of both boards', () {
      final puzzle = SamuraiEngine.generate(
        difficulty: SudokuDifficulty.beginner,
        seed: 88,
      );
      final overlap = SamuraiTopology.indexOf(6, 6);
      final board = List<int>.from(puzzle.solution);
      final correctValue = board[overlap];
      board[overlap] = 0;

      expect(SamuraiEngine.canPlace(board, overlap, correctValue), isTrue);

      final peer = SamuraiTopology.units[
        SamuraiTopology.unitsByCell[overlap].first
      ].firstWhere((index) => index != overlap);
      board[peer] = correctValue;
      expect(SamuraiEngine.canPlace(board, overlap, correctValue), isFalse);
    });

    test('recognizes a completed Samurai board', () {
      final puzzle = SamuraiEngine.generate(
        difficulty: SudokuDifficulty.beginner,
        seed: 120,
      );
      expect(
        SamuraiEngine.isComplete(puzzle, List<int>.from(puzzle.solution)),
        isTrue,
      );
    });
  });
}
