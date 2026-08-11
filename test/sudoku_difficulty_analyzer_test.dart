import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/domain/sudoku.dart';
import 'package:sudoku_game/domain/sudoku_difficulty_analyzer.dart';

void main() {
  test('solves a single-gap puzzle with a naked single', () {
    const puzzle = SudokuPuzzle(
      id: 'single-gap',
      difficulty: SudokuDifficulty.beginner,
      puzzle: <int>[1, 2, 3, 0, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
      solution: <int>[1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
      size: 4,
      boxRows: 2,
      boxColumns: 2,
    );

    final analysis = SudokuDifficultyAnalyzer.analyze(puzzle);

    expect(analysis.solved, isTrue);
    expect(analysis.hardestTechnique, SudokuTechnique.nakedSingle);
    expect(analysis.searchNodes, 0);
    expect(analysis.difficulty, SudokuDifficulty.beginner);
  });

  test('generated puzzles remain solvable and receive a bounded grade', () {
    for (final difficulty in SudokuDifficulty.values) {
      final puzzle = SudokuEngine.generate(
        difficulty: difficulty,
        seed: 9000 + difficulty.index,
      );
      final analysis = SudokuDifficultyAnalyzer.analyze(puzzle);

      expect(analysis.solved, isTrue, reason: difficulty.name);
      expect(
        analysis.difficulty.index,
        inInclusiveRange(0, SudokuDifficulty.values.length - 1),
      );
      expect(analysis.logicalSteps, greaterThanOrEqualTo(0));
      expect(analysis.searchNodes, greaterThanOrEqualTo(0));
    }
  });

  test('seeded generation is deterministic and distinct across levels', () {
    final first = SudokuEngine.generate(
      difficulty: SudokuDifficulty.medium,
      seed: 42,
    );
    final repeated = SudokuEngine.generate(
      difficulty: SudokuDifficulty.medium,
      seed: 42,
    );
    final other = SudokuEngine.generate(
      difficulty: SudokuDifficulty.medium,
      seed: 43,
    );

    expect(repeated.puzzle, first.puzzle);
    expect(repeated.solution, first.solution);
    expect(other.id, isNot(first.id));
    expect(other.puzzle, isNot(first.puzzle));
  });
}
