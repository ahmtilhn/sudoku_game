import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/puzzle_catalog.dart';
import 'package:sudoku_game/domain/sudoku.dart';

void main() {
  group('SudokuEngine', () {
    test('catalog puzzles have a valid shape and solution', () {
      for (final puzzle in PuzzleCatalog.careerPuzzles) {
        expect(
          SudokuEngine.isPuzzleShapeValid(puzzle),
          isTrue,
          reason: puzzle.id,
        );
      }
    });

    test('rejects a duplicate in the same row', () {
      final puzzle = PuzzleCatalog.careerPuzzles.first;
      final board = List<int>.filled(81, 0)..[0] = 5;
      expect(SudokuEngine.canPlace(puzzle, board, 1, 5), isFalse);
    });

    test('returns legal candidates for an empty cell', () {
      final puzzle = PuzzleCatalog.careerPuzzles.firstWhere(
        (item) => item.difficulty == SudokuDifficulty.easy,
      );
      final candidates = SudokuEngine.candidates(
        puzzle,
        List<int>.from(puzzle.puzzle),
        2,
      );
      expect(candidates, contains(puzzle.solution[2]));
    });

    test('recognizes a completed board', () {
      final puzzle = PuzzleCatalog.careerPuzzles.last;
      expect(
        SudokuEngine.isComplete(puzzle, List<int>.from(puzzle.solution)),
        isTrue,
      );
    });
  });
}
