import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/domain/classic16_puzzle_factory.dart';
import 'package:sudoku_game/domain/sudoku.dart';

void main() {
  test('generates a valid numeric 16x16 puzzle', () {
    final puzzle = Classic16PuzzleFactory.generate(
      difficulty: SudokuDifficulty.medium,
      seed: 42,
    );

    expect(puzzle.size, 16);
    expect(puzzle.boxRows, 4);
    expect(puzzle.boxColumns, 4);
    expect(puzzle.puzzle, hasLength(256));
    expect(puzzle.solution, hasLength(256));
    expect(puzzle.solution, contains(16));
    expect(puzzle.puzzle.every((value) => value >= 0 && value <= 16), isTrue);
    expect(SudokuEngine.isPuzzleShapeValid(puzzle), isTrue);
  });

  test('difficulty changes the number of visible clues', () {
    final beginner = Classic16PuzzleFactory.generate(
      difficulty: SudokuDifficulty.beginner,
      seed: 7,
    );
    final expert = Classic16PuzzleFactory.generate(
      difficulty: SudokuDifficulty.expert,
      seed: 7,
    );

    final beginnerClues = beginner.puzzle.where((value) => value != 0).length;
    final expertClues = expert.puzzle.where((value) => value != 0).length;
    expect(beginnerClues, greaterThan(expertClues));
  });
}
