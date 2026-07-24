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
    required this.title,
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
}
