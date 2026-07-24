import 'dart:math';

import '../domain/sudoku.dart';

class PuzzleCatalog {
  const PuzzleCatalog._();

  /// Compatibility samples used by tests and development tools. Career mode
  /// itself generates a fresh puzzle whenever the player starts a game.
  static final List<SudokuPuzzle> careerPuzzles = <SudokuPuzzle>[
    for (var index = 0; index < SudokuDifficulty.values.length; index++)
      generatePuzzle(
        SudokuDifficulty.values[index],
        seed: 1000 + index,
        idPrefix: 'sample',
      ),
  ];

  static SudokuPuzzle generatePuzzle(
    SudokuDifficulty difficulty, {
    int? seed,
    String idPrefix = 'career-random',
    String? title,
  }) {
    final actualSeed = seed ??
        DateTime.now().microsecondsSinceEpoch ^
            Object().hashCode ^
            Random().nextInt(1 << 31);
    final random = Random(actualSeed);
    final solution = _generateSolvedGrid(random);
    final puzzle = _carveUniquePuzzle(
      solution,
      difficulty: difficulty,
      random: random,
    );

    return SudokuPuzzle(
      id: '$idPrefix-${difficulty.name}-${actualSeed.abs()}',
      title: title ?? difficulty.label,
      difficulty: difficulty,
      puzzle: puzzle,
      solution: solution,
    );
  }

  static SudokuPuzzle dailyPuzzle(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final seed = normalized.difference(DateTime(2025)).inDays.abs();
    return generatePuzzle(
      SudokuDifficulty.medium,
      seed: seed,
      idPrefix: 'daily',
      title: 'Daily Sudoku',
    );
  }

  static SudokuPuzzle duelPuzzle({
    required SudokuDifficulty difficulty,
    int seed = 0,
  }) {
    return generatePuzzle(
      difficulty,
      seed: seed,
      idPrefix: 'duel',
      title: 'Duel',
    );
  }

  static const SudokuPuzzle tutorialPuzzle = SudokuPuzzle(
    id: 'tutorial-4x4',
    title: 'Mini Sudoku',
    difficulty: SudokuDifficulty.beginner,
    size: 4,
    boxRows: 2,
    boxColumns: 2,
    puzzle: <int>[1, 0, 0, 4, 0, 4, 1, 0, 0, 1, 4, 0, 4, 0, 0, 1],
    solution: <int>[1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
  );

  static int targetClueCount(SudokuDifficulty difficulty) => switch (difficulty) {
        SudokuDifficulty.beginner => 48,
        SudokuDifficulty.easy => 42,
        SudokuDifficulty.medium => 36,
        SudokuDifficulty.hard => 31,
        SudokuDifficulty.expert => 27,
      };

  static bool hasUniqueSolution(List<int> puzzle) {
    if (puzzle.length != 81) return false;
    return _countSolutions(List<int>.from(puzzle), limit: 2) == 1;
  }

  static List<int> _generateSolvedGrid(Random random) {
    const side = 3;
    const size = 9;

    int pattern(int row, int column) =>
        (side * (row % side) + row ~/ side + column) % size;

    final bands = <int>[0, 1, 2]..shuffle(random);
    final stacks = <int>[0, 1, 2]..shuffle(random);
    final rows = <int>[
      for (final band in bands)
        ...(<int>[0, 1, 2]..shuffle(random)).map(
          (offset) => band * side + offset,
        ),
    ];
    final columns = <int>[
      for (final stack in stacks)
        ...(<int>[0, 1, 2]..shuffle(random)).map(
          (offset) => stack * side + offset,
        ),
    ];
    final numbers = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9]
      ..shuffle(random);

    return <int>[
      for (final row in rows)
        for (final column in columns) numbers[pattern(row, column)],
    ];
  }

  static List<int> _carveUniquePuzzle(
    List<int> solution, {
    required SudokuDifficulty difficulty,
    required Random random,
  }) {
    final puzzle = List<int>.from(solution);
    final cells = List<int>.generate(81, (index) => index)..shuffle(random);
    final targetClues = targetClueCount(difficulty);
    var clueCount = 81;

    for (final index in cells) {
      if (clueCount <= targetClues) break;
      final previous = puzzle[index];
      puzzle[index] = 0;
      if (_countSolutions(List<int>.from(puzzle), limit: 2) == 1) {
        clueCount--;
      } else {
        puzzle[index] = previous;
      }
    }

    return puzzle;
  }

  static int _countSolutions(List<int> board, {required int limit}) {
    var selectedIndex = -1;
    List<int>? selectedCandidates;

    for (var index = 0; index < board.length; index++) {
      if (board[index] != 0) continue;
      final candidates = _legalValues(board, index);
      if (candidates.isEmpty) return 0;
      if (selectedCandidates == null ||
          candidates.length < selectedCandidates.length) {
        selectedIndex = index;
        selectedCandidates = candidates;
        if (candidates.length == 1) break;
      }
    }

    if (selectedIndex == -1) return 1;

    var count = 0;
    for (final value in selectedCandidates!) {
      board[selectedIndex] = value;
      count += _countSolutions(board, limit: limit);
      board[selectedIndex] = 0;
      if (count >= limit) return count;
    }
    return count;
  }

  static List<int> _legalValues(List<int> board, int index) {
    final used = <int>{};
    final row = index ~/ 9;
    final column = index % 9;

    for (var cursor = 0; cursor < 9; cursor++) {
      used.add(board[row * 9 + cursor]);
      used.add(board[cursor * 9 + column]);
    }

    final boxRow = (row ~/ 3) * 3;
    final boxColumn = (column ~/ 3) * 3;
    for (var rowOffset = 0; rowOffset < 3; rowOffset++) {
      for (var columnOffset = 0; columnOffset < 3; columnOffset++) {
        used.add(board[(boxRow + rowOffset) * 9 + boxColumn + columnOffset]);
      }
    }

    return <int>[
      for (var value = 1; value <= 9; value++)
        if (!used.contains(value)) value,
    ];
  }
}
