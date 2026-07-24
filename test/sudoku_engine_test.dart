import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/puzzle_catalog.dart';
import 'package:sudoku_game/domain/sudoku.dart';

void main() {
  group('SudokuEngine', () {
    test('generated puzzles have a valid shape and one solution', () {
      for (var index = 0; index < SudokuDifficulty.values.length; index++) {
        final difficulty = SudokuDifficulty.values[index];
        final puzzle = PuzzleCatalog.generatePuzzle(
          difficulty,
          seed: 5000 + index,
        );
        expect(
          SudokuEngine.isPuzzleShapeValid(puzzle),
          isTrue,
          reason: difficulty.name,
        );
        expect(
          PuzzleCatalog.hasUniqueSolution(puzzle.puzzle),
          isTrue,
          reason: difficulty.name,
        );
        expect(
          puzzle.puzzle.where((value) => value != 0).length,
          greaterThanOrEqualTo(PuzzleCatalog.targetClueCount(difficulty)),
        );
      }
    });

    test('the same seed produces the same puzzle', () {
      final first = PuzzleCatalog.generatePuzzle(
        SudokuDifficulty.medium,
        seed: 99123,
      );
      final second = PuzzleCatalog.generatePuzzle(
        SudokuDifficulty.medium,
        seed: 99123,
      );
      expect(second.puzzle, equals(first.puzzle));
      expect(second.solution, equals(first.solution));
    });

    test('different seeds produce different boards', () {
      final first = PuzzleCatalog.generatePuzzle(
        SudokuDifficulty.easy,
        seed: 101,
      );
      final second = PuzzleCatalog.generatePuzzle(
        SudokuDifficulty.easy,
        seed: 202,
      );
      expect(second.puzzle, isNot(equals(first.puzzle)));
    });

    test('duel puzzle keeps the selected difficulty', () {
      final puzzle = PuzzleCatalog.duelPuzzle(
        difficulty: SudokuDifficulty.hard,
        seed: 77,
      );
      expect(puzzle.difficulty, SudokuDifficulty.hard);
      expect(PuzzleCatalog.hasUniqueSolution(puzzle.puzzle), isTrue);
    });

    test('rejects a duplicate in the same row', () {
      final puzzle = PuzzleCatalog.generatePuzzle(
        SudokuDifficulty.beginner,
        seed: 12,
      );
      final board = List<int>.filled(81, 0)..[0] = 5;
      expect(SudokuEngine.canPlace(puzzle, board, 1, 5), isFalse);
    });

    test('returns legal candidates for an empty cell', () {
      final puzzle = PuzzleCatalog.generatePuzzle(
        SudokuDifficulty.easy,
        seed: 14,
      );
      final index = puzzle.puzzle.indexOf(0);
      final candidates = SudokuEngine.candidates(
        puzzle,
        List<int>.from(puzzle.puzzle),
        index,
      );
      expect(candidates, contains(puzzle.solution[index]));
    });

    test('recognizes a completed board', () {
      final puzzle = PuzzleCatalog.generatePuzzle(
        SudokuDifficulty.expert,
        seed: 18,
      );
      expect(
        SudokuEngine.isComplete(puzzle, List<int>.from(puzzle.solution)),
        isTrue,
      );
    });
  });
}
