import 'dart:math';

enum SudokuDifficulty { beginner, easy, medium, hard, expert }

extension SudokuDifficultyLabel on SudokuDifficulty {
  String get label => switch (this) {
    SudokuDifficulty.beginner => 'Beginner',
    SudokuDifficulty.easy => 'Easy',
    SudokuDifficulty.medium => 'Medium',
    SudokuDifficulty.hard => 'Hard',
    SudokuDifficulty.expert => 'Expert',
  };
}

class SudokuPuzzle {
  const SudokuPuzzle({
    required this.id,
    this.title = '',
    required this.difficulty,
    required this.puzzle,
    required this.solution,
    this.size = 9,
    this.boxRows = 3,
    this.boxColumns = 3,
  });

  final String id;
  final String title;
  final SudokuDifficulty difficulty;
  final List<int> puzzle;
  final List<int> solution;
  final int size;
  final int boxRows;
  final int boxColumns;

  int get cellCount => size * size;

  bool isFixed(int index) => puzzle[index] != 0;

  SudokuPuzzle copyWith({
    String? id,
    String? title,
    SudokuDifficulty? difficulty,
    List<int>? puzzle,
    List<int>? solution,
  }) {
    return SudokuPuzzle(
      id: id ?? this.id,
      title: title ?? this.title,
      difficulty: difficulty ?? this.difficulty,
      puzzle: puzzle ?? this.puzzle,
      solution: solution ?? this.solution,
      size: size,
      boxRows: boxRows,
      boxColumns: boxColumns,
    );
  }
}

class SudokuEngine {
  const SudokuEngine._();

  /// Generates a deterministic, uniquely solvable Sudoku when [seed] is set.
  ///
  /// The production game uses 9×9 boards and the first career lessons use 4×4
  /// boards. Keeping generation in the pure Dart domain layer ensures career,
  /// tests, daily puzzles and development tools all use the same rules.
  static SudokuPuzzle generate({
    required SudokuDifficulty difficulty,
    int size = 9,
    int? seed,
    String? id,
    String? title,
  }) {
    final boxSize = sqrt(size).toInt();
    if (boxSize * boxSize != size || (size != 4 && size != 9)) {
      throw ArgumentError.value(
        size,
        'size',
        'Only square 4×4 and 9×9 Sudoku boards are supported.',
      );
    }

    final actualSeed =
        seed ??
        DateTime.now().microsecondsSinceEpoch ^
            Object().hashCode ^
            Random().nextInt(1 << 31);
    final random = Random(actualSeed);
    final solution = _generateSolvedGrid(
      size: size,
      boxSize: boxSize,
      random: random,
    );
    final puzzle = _carveUniquePuzzle(
      solution,
      size: size,
      boxSize: boxSize,
      targetClues: _targetClueCount(difficulty, size),
      random: random,
    );

    return SudokuPuzzle(
      id: id ?? 'generated-${difficulty.name}-${actualSeed.abs()}',
      title: title ?? difficulty.label,
      difficulty: difficulty,
      puzzle: List<int>.unmodifiable(puzzle),
      solution: List<int>.unmodifiable(solution),
      size: size,
      boxRows: boxSize,
      boxColumns: boxSize,
    );
  }

  static bool hasUniqueSolution(SudokuPuzzle puzzle) {
    if (!isPuzzleShapeValid(puzzle)) return false;
    return _countSolutions(
          List<int>.from(puzzle.puzzle),
          size: puzzle.size,
          boxRows: puzzle.boxRows,
          boxColumns: puzzle.boxColumns,
          limit: 2,
        ) ==
        1;
  }

  static bool isPuzzleShapeValid(SudokuPuzzle puzzle) {
    if (puzzle.size <= 0 || puzzle.boxRows <= 0 || puzzle.boxColumns <= 0) {
      return false;
    }
    if (puzzle.boxRows * puzzle.boxColumns != puzzle.size) {
      return false;
    }
    if (puzzle.puzzle.length != puzzle.cellCount ||
        puzzle.solution.length != puzzle.cellCount) {
      return false;
    }
    for (var index = 0; index < puzzle.cellCount; index++) {
      final clue = puzzle.puzzle[index];
      final answer = puzzle.solution[index];
      if (answer < 1 || answer > puzzle.size) {
        return false;
      }
      if (clue < 0 || clue > puzzle.size) {
        return false;
      }
      if (clue != 0 && clue != answer) {
        return false;
      }
    }
    return isSolvedBoardValid(puzzle, puzzle.solution);
  }

  static bool isSolvedBoardValid(SudokuPuzzle puzzle, List<int> board) {
    if (board.length != puzzle.cellCount) {
      return false;
    }
    for (var index = 0; index < board.length; index++) {
      final value = board[index];
      if (value < 1 || value > puzzle.size) {
        return false;
      }
      final copy = List<int>.from(board)..[index] = 0;
      if (!canPlace(puzzle, copy, index, value)) {
        return false;
      }
    }
    return true;
  }

  static bool canPlace(
    SudokuPuzzle puzzle,
    List<int> board,
    int index,
    int value,
  ) {
    if (index < 0 || index >= puzzle.cellCount) {
      return false;
    }
    if (value < 1 || value > puzzle.size) {
      return false;
    }

    final row = index ~/ puzzle.size;
    final column = index % puzzle.size;

    for (var cursor = 0; cursor < puzzle.size; cursor++) {
      final rowIndex = row * puzzle.size + cursor;
      final columnIndex = cursor * puzzle.size + column;
      if (rowIndex != index && board[rowIndex] == value) {
        return false;
      }
      if (columnIndex != index && board[columnIndex] == value) {
        return false;
      }
    }

    final boxStartRow = (row ~/ puzzle.boxRows) * puzzle.boxRows;
    final boxStartColumn = (column ~/ puzzle.boxColumns) * puzzle.boxColumns;
    for (var rowOffset = 0; rowOffset < puzzle.boxRows; rowOffset++) {
      for (
        var columnOffset = 0;
        columnOffset < puzzle.boxColumns;
        columnOffset++
      ) {
        final boxIndex =
            (boxStartRow + rowOffset) * puzzle.size +
            boxStartColumn +
            columnOffset;
        if (boxIndex != index && board[boxIndex] == value) {
          return false;
        }
      }
    }
    return true;
  }

  static Set<int> candidates(SudokuPuzzle puzzle, List<int> board, int index) {
    if (index < 0 || index >= puzzle.cellCount || board[index] != 0) {
      return const <int>{};
    }
    return {
      for (var value = 1; value <= puzzle.size; value++)
        if (canPlace(puzzle, board, index, value)) value,
    };
  }

  static bool isComplete(SudokuPuzzle puzzle, List<int> board) {
    if (board.length != puzzle.cellCount || board.contains(0)) {
      return false;
    }
    for (var index = 0; index < board.length; index++) {
      if (board[index] != puzzle.solution[index]) {
        return false;
      }
    }
    return true;
  }

  static int relatedBoxIndex(SudokuPuzzle puzzle, int index) {
    final row = index ~/ puzzle.size;
    final column = index % puzzle.size;
    final boxRow = row ~/ puzzle.boxRows;
    final boxColumn = column ~/ puzzle.boxColumns;
    return boxRow * (puzzle.size ~/ puzzle.boxColumns) + boxColumn;
  }

  static List<int> _generateSolvedGrid({
    required int size,
    required int boxSize,
    required Random random,
  }) {
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
    final numbers = List<int>.generate(size, (index) => index + 1)
      ..shuffle(random);

    return <int>[
      for (final row in rows)
        for (final column in columns) numbers[pattern(row, column)],
    ];
  }

  static List<int> _carveUniquePuzzle(
    List<int> solution, {
    required int size,
    required int boxSize,
    required int targetClues,
    required Random random,
  }) {
    final puzzle = List<int>.from(solution);
    final cells = List<int>.generate(size * size, (index) => index)
      ..shuffle(random);
    var clueCount = puzzle.length;

    for (final index in cells) {
      if (clueCount <= targetClues) break;
      final previous = puzzle[index];
      puzzle[index] = 0;
      final solutions = _countSolutions(
        puzzle,
        size: size,
        boxRows: boxSize,
        boxColumns: boxSize,
        limit: 2,
      );
      if (solutions == 1) {
        clueCount--;
      } else {
        puzzle[index] = previous;
      }
    }
    return puzzle;
  }

  static int _countSolutions(
    List<int> board, {
    required int size,
    required int boxRows,
    required int boxColumns,
    required int limit,
  }) {
    var selectedIndex = -1;
    List<int>? selectedCandidates;

    for (var index = 0; index < board.length; index++) {
      if (board[index] != 0) continue;
      final candidates = _legalValues(
        board,
        index,
        size: size,
        boxRows: boxRows,
        boxColumns: boxColumns,
      );
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
      count += _countSolutions(
        board,
        size: size,
        boxRows: boxRows,
        boxColumns: boxColumns,
        limit: limit,
      );
      board[selectedIndex] = 0;
      if (count >= limit) return count;
    }
    return count;
  }

  static List<int> _legalValues(
    List<int> board,
    int index, {
    required int size,
    required int boxRows,
    required int boxColumns,
  }) {
    final used = <int>{};
    final row = index ~/ size;
    final column = index % size;

    for (var cursor = 0; cursor < size; cursor++) {
      used.add(board[row * size + cursor]);
      used.add(board[cursor * size + column]);
    }

    final boxRow = (row ~/ boxRows) * boxRows;
    final boxColumn = (column ~/ boxColumns) * boxColumns;
    for (var rowOffset = 0; rowOffset < boxRows; rowOffset++) {
      for (var columnOffset = 0; columnOffset < boxColumns; columnOffset++) {
        used.add(board[(boxRow + rowOffset) * size + boxColumn + columnOffset]);
      }
    }

    return <int>[
      for (var value = 1; value <= size; value++)
        if (!used.contains(value)) value,
    ];
  }

  static int _targetClueCount(SudokuDifficulty difficulty, int size) {
    if (size == 4) {
      return switch (difficulty) {
        SudokuDifficulty.beginner => 9,
        SudokuDifficulty.easy => 8,
        SudokuDifficulty.medium => 7,
        SudokuDifficulty.hard => 6,
        SudokuDifficulty.expert => 5,
      };
    }
    return switch (difficulty) {
      SudokuDifficulty.beginner => 48,
      SudokuDifficulty.easy => 42,
      SudokuDifficulty.medium => 36,
      SudokuDifficulty.hard => 31,
      SudokuDifficulty.expert => 27,
    };
  }
}
