import 'dart:math';

import 'sudoku.dart';

class Classic16PuzzleFactory {
  const Classic16PuzzleFactory._();

  static SudokuPuzzle generate({
    required SudokuDifficulty difficulty,
    int? seed,
    String? id,
    String? title,
  }) {
    final actualSeed = seed ?? DateTime.now().microsecondsSinceEpoch;
    final random = Random(actualSeed);
    const size = 16;
    const boxSize = 4;

    int pattern(int row, int column) =>
        (boxSize * (row % boxSize) + row ~/ boxSize + column) % size;

    final bands = List<int>.generate(boxSize, (index) => index)
      ..shuffle(random);
    final stacks = List<int>.generate(boxSize, (index) => index)
      ..shuffle(random);
    final rows = <int>[
      for (final band in bands)
        ...(List<int>.generate(
          boxSize,
          (index) => index,
        )..shuffle(random)).map((offset) => band * boxSize + offset),
    ];
    final columns = <int>[
      for (final stack in stacks)
        ...(List<int>.generate(
          boxSize,
          (index) => index,
        )..shuffle(random)).map((offset) => stack * boxSize + offset),
    ];
    final values = List<int>.generate(size, (index) => index + 1)
      ..shuffle(random);
    final solution = <int>[
      for (final row in rows)
        for (final column in columns) values[pattern(row, column)],
    ];
    final puzzle = List<int>.from(solution);
    final passes = switch (difficulty) {
      SudokuDifficulty.beginner => 4,
      SudokuDifficulty.easy => 5,
      SudokuDifficulty.medium => 6,
      SudokuDifficulty.hard => 7,
      SudokuDifficulty.expert => 8,
    };
    final offset = random.nextInt(size);
    for (var pass = 0; pass < passes; pass++) {
      for (var row = 0; row < size; row++) {
        final column = (row * 5 + pass * 3 + offset) % size;
        puzzle[row * size + column] = 0;
      }
    }

    return SudokuPuzzle(
      id: id ?? 'classic16-${difficulty.name}-${actualSeed.abs()}',
      title: title ?? '16×16 ${difficulty.label}',
      difficulty: difficulty,
      puzzle: List<int>.unmodifiable(puzzle),
      solution: List<int>.unmodifiable(solution),
      size: size,
      boxRows: boxSize,
      boxColumns: boxSize,
    );
  }
}
