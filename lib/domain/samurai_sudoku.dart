import 'dart:math';

import 'sudoku.dart';

/// A Samurai Sudoku is rendered on a 21×21 canvas and contains five
/// overlapping 9×9 Sudoku boards. Inactive canvas cells use [inactiveCell].
class SamuraiTopology {
  const SamuraiTopology._();

  static const int canvasSize = 21;
  static const int canvasCellCount = canvasSize * canvasSize;
  static const int boardSize = 9;
  static const int activeCellCount = 369;
  static const int inactiveCell = -1;

  static const List<SamuraiBoardOrigin> boardOrigins = <SamuraiBoardOrigin>[
    SamuraiBoardOrigin(row: 0, column: 0),
    SamuraiBoardOrigin(row: 0, column: 12),
    SamuraiBoardOrigin(row: 6, column: 6),
    SamuraiBoardOrigin(row: 12, column: 0),
    SamuraiBoardOrigin(row: 12, column: 12),
  ];

  static final List<int> activeIndexes = List<int>.unmodifiable(
    <int>[
      for (var index = 0; index < canvasCellCount; index++)
        if (isActiveIndex(index)) index,
    ],
  );

  static final List<List<int>> units = List<List<int>>.unmodifiable(
    _createUnits().map(List<int>.unmodifiable),
  );

  static final List<List<int>> unitsByCell = List<List<int>>.unmodifiable(
    _createUnitsByCell().map(List<int>.unmodifiable),
  );

  static int indexOf(int row, int column) => row * canvasSize + column;

  static int rowOf(int index) => index ~/ canvasSize;

  static int columnOf(int index) => index % canvasSize;

  static bool isActiveIndex(int index) {
    if (index < 0 || index >= canvasCellCount) return false;
    final row = rowOf(index);
    final column = columnOf(index);
    return boardOrigins.any(
      (origin) =>
          row >= origin.row &&
          row < origin.row + boardSize &&
          column >= origin.column &&
          column < origin.column + boardSize,
    );
  }

  static bool isOverlapIndex(int index) {
    if (!isActiveIndex(index)) return false;
    final row = rowOf(index);
    final column = columnOf(index);
    var memberships = 0;
    for (final origin in boardOrigins) {
      if (row >= origin.row &&
          row < origin.row + boardSize &&
          column >= origin.column &&
          column < origin.column + boardSize) {
        memberships++;
      }
    }
    return memberships == 2;
  }

  static List<List<int>> _createUnits() {
    final result = <List<int>>[];
    for (final origin in boardOrigins) {
      for (var localRow = 0; localRow < boardSize; localRow++) {
        result.add(<int>[
          for (var localColumn = 0;
              localColumn < boardSize;
              localColumn++)
            indexOf(origin.row + localRow, origin.column + localColumn),
        ]);
      }
      for (var localColumn = 0;
          localColumn < boardSize;
          localColumn++) {
        result.add(<int>[
          for (var localRow = 0; localRow < boardSize; localRow++)
            indexOf(origin.row + localRow, origin.column + localColumn),
        ]);
      }
      for (var box = 0; box < boardSize; box++) {
        final boxRow = (box ~/ 3) * 3;
        final boxColumn = (box % 3) * 3;
        result.add(<int>[
          for (var rowOffset = 0; rowOffset < 3; rowOffset++)
            for (var columnOffset = 0; columnOffset < 3; columnOffset++)
              indexOf(
                origin.row + boxRow + rowOffset,
                origin.column + boxColumn + columnOffset,
              ),
        ]);
      }
    }
    return result;
  }

  static List<List<int>> _createUnitsByCell() {
    final result = List<List<int>>.generate(
      canvasCellCount,
      (_) => <int>[],
    );
    for (var unitIndex = 0; unitIndex < units.length; unitIndex++) {
      for (final cellIndex in units[unitIndex]) {
        result[cellIndex].add(unitIndex);
      }
    }
    return result;
  }
}

class SamuraiBoardOrigin {
  const SamuraiBoardOrigin({required this.row, required this.column});

  final int row;
  final int column;
}

class SamuraiPuzzle {
  const SamuraiPuzzle({
    required this.id,
    required this.difficulty,
    required this.puzzle,
    required this.solution,
    this.title = 'Samurai Sudoku',
  });

  final String id;
  final String title;
  final SudokuDifficulty difficulty;
  final List<int> puzzle;
  final List<int> solution;

  int get cellCount => SamuraiTopology.canvasCellCount;

  int get clueCount => puzzle.where((value) => value > 0).length;

  bool isActive(int index) => SamuraiTopology.isActiveIndex(index);

  bool isFixed(int index) => isActive(index) && puzzle[index] > 0;
}

class SamuraiEngine {
  const SamuraiEngine._();

  static SamuraiPuzzle generate({
    required SudokuDifficulty difficulty,
    int? seed,
    String? id,
    String title = 'Samurai Sudoku',
  }) {
    final actualSeed =
        seed ??
        DateTime.now().microsecondsSinceEpoch ^
            Object().hashCode ^
            Random().nextInt(1 << 31);
    final random = Random(actualSeed);
    final solution = _generateSolution(random);
    final puzzle = _carveUniquePuzzle(
      solution,
      targetClues: _targetClueCount(difficulty),
      random: random,
    );
    return SamuraiPuzzle(
      id: id ?? 'samurai-${difficulty.name}-${actualSeed.abs()}',
      title: title,
      difficulty: difficulty,
      puzzle: List<int>.unmodifiable(puzzle),
      solution: List<int>.unmodifiable(solution),
    );
  }

  static bool isPuzzleShapeValid(SamuraiPuzzle puzzle) {
    if (puzzle.puzzle.length != SamuraiTopology.canvasCellCount ||
        puzzle.solution.length != SamuraiTopology.canvasCellCount) {
      return false;
    }
    for (var index = 0; index < SamuraiTopology.canvasCellCount; index++) {
      final clue = puzzle.puzzle[index];
      final answer = puzzle.solution[index];
      if (!SamuraiTopology.isActiveIndex(index)) {
        if (clue != SamuraiTopology.inactiveCell ||
            answer != SamuraiTopology.inactiveCell) {
          return false;
        }
        continue;
      }
      if (answer < 1 || answer > 9 || clue < 0 || clue > 9) {
        return false;
      }
      if (clue != 0 && clue != answer) return false;
    }
    return isSolvedBoardValid(puzzle.solution);
  }

  static bool isSolvedBoardValid(List<int> board) {
    if (board.length != SamuraiTopology.canvasCellCount) return false;
    for (var index = 0; index < board.length; index++) {
      if (!SamuraiTopology.isActiveIndex(index)) {
        if (board[index] != SamuraiTopology.inactiveCell) return false;
        continue;
      }
      final value = board[index];
      if (value < 1 || value > 9) return false;
    }
    for (final unit in SamuraiTopology.units) {
      var mask = 0;
      for (final index in unit) {
        final bit = 1 << (board[index] - 1);
        if ((mask & bit) != 0) return false;
        mask |= bit;
      }
      if (mask != 0x1ff) return false;
    }
    return true;
  }

  static bool canPlace(List<int> board, int index, int value) {
    if (board.length != SamuraiTopology.canvasCellCount ||
        !SamuraiTopology.isActiveIndex(index) ||
        value < 1 ||
        value > 9) {
      return false;
    }
    for (final unitIndex in SamuraiTopology.unitsByCell[index]) {
      for (final peerIndex in SamuraiTopology.units[unitIndex]) {
        if (peerIndex != index && board[peerIndex] == value) return false;
      }
    }
    return true;
  }

  static Set<int> candidates(List<int> board, int index) {
    if (board.length != SamuraiTopology.canvasCellCount ||
        !SamuraiTopology.isActiveIndex(index) ||
        board[index] != 0) {
      return const <int>{};
    }
    return <int>{
      for (var value = 1; value <= 9; value++)
        if (canPlace(board, index, value)) value,
    };
  }

  static bool isComplete(SamuraiPuzzle puzzle, List<int> board) {
    if (board.length != SamuraiTopology.canvasCellCount) return false;
    for (final index in SamuraiTopology.activeIndexes) {
      if (board[index] != puzzle.solution[index]) return false;
    }
    return true;
  }

  static bool hasUniqueSolution(SamuraiPuzzle puzzle) {
    if (!isPuzzleShapeValid(puzzle)) return false;
    return _countSolutions(List<int>.from(puzzle.puzzle), limit: 2) == 1;
  }

  static List<int> _generateSolution(Random random) {
    final base = <int>[
      for (var row = 0; row < 9; row++)
        for (var column = 0; column < 9; column++)
          (3 * (row % 3) + row ~/ 3 + column) % 9 + 1,
    ];
    final digits = List<int>.generate(9, (index) => index + 1)
      ..shuffle(random);
    final center = base.map((value) => digits[value - 1]).toList();

    final topLeft = _mapGridToOverlap(
      base,
      sourceRow: 6,
      sourceColumn: 6,
      targetGrid: center,
      targetRow: 0,
      targetColumn: 0,
    );
    final topRight = _mapGridToOverlap(
      base,
      sourceRow: 6,
      sourceColumn: 0,
      targetGrid: center,
      targetRow: 0,
      targetColumn: 6,
    );
    final bottomLeft = _mapGridToOverlap(
      base,
      sourceRow: 0,
      sourceColumn: 6,
      targetGrid: center,
      targetRow: 6,
      targetColumn: 0,
    );
    final bottomRight = _mapGridToOverlap(
      base,
      sourceRow: 0,
      sourceColumn: 0,
      targetGrid: center,
      targetRow: 6,
      targetColumn: 6,
    );

    final canvas = List<int>.filled(
      SamuraiTopology.canvasCellCount,
      SamuraiTopology.inactiveCell,
    );
    _placeGrid(canvas, topLeft, SamuraiTopology.boardOrigins[0]);
    _placeGrid(canvas, topRight, SamuraiTopology.boardOrigins[1]);
    _placeGrid(canvas, center, SamuraiTopology.boardOrigins[2]);
    _placeGrid(canvas, bottomLeft, SamuraiTopology.boardOrigins[3]);
    _placeGrid(canvas, bottomRight, SamuraiTopology.boardOrigins[4]);
    return canvas;
  }

  static List<int> _mapGridToOverlap(
    List<int> source, {
    required int sourceRow,
    required int sourceColumn,
    required List<int> targetGrid,
    required int targetRow,
    required int targetColumn,
  }) {
    final mapping = <int, int>{};
    for (var rowOffset = 0; rowOffset < 3; rowOffset++) {
      for (var columnOffset = 0; columnOffset < 3; columnOffset++) {
        final sourceValue =
            source[(sourceRow + rowOffset) * 9 + sourceColumn + columnOffset];
        final targetValue =
            targetGrid[(targetRow + rowOffset) * 9 +
                targetColumn +
                columnOffset];
        mapping[sourceValue] = targetValue;
      }
    }
    return source.map((value) => mapping[value]!).toList();
  }

  static void _placeGrid(
    List<int> canvas,
    List<int> grid,
    SamuraiBoardOrigin origin,
  ) {
    for (var localRow = 0; localRow < 9; localRow++) {
      for (var localColumn = 0; localColumn < 9; localColumn++) {
        final canvasIndex = SamuraiTopology.indexOf(
          origin.row + localRow,
          origin.column + localColumn,
        );
        final value = grid[localRow * 9 + localColumn];
        final previous = canvas[canvasIndex];
        if (previous != SamuraiTopology.inactiveCell && previous != value) {
          throw StateError('Samurai overlap contains conflicting values.');
        }
        canvas[canvasIndex] = value;
      }
    }
  }

  static List<int> _carveUniquePuzzle(
    List<int> solution, {
    required int targetClues,
    required Random random,
  }) {
    final puzzle = List<int>.from(solution);
    final candidates = List<int>.from(SamuraiTopology.activeIndexes)
      ..shuffle(random);
    var clues = SamuraiTopology.activeCellCount;
    for (final index in candidates) {
      if (clues <= targetClues) break;
      final previous = puzzle[index];
      puzzle[index] = 0;
      if (_countSolutions(puzzle, limit: 2) == 1) {
        clues--;
      } else {
        puzzle[index] = previous;
      }
    }
    return puzzle;
  }

  static int _countSolutions(List<int> board, {required int limit}) {
    if (board.length != SamuraiTopology.canvasCellCount) return 0;
    final masks = List<int>.filled(SamuraiTopology.units.length, 0);
    for (final index in SamuraiTopology.activeIndexes) {
      final value = board[index];
      if (value == 0) continue;
      if (value < 1 || value > 9) return 0;
      final bit = 1 << (value - 1);
      for (final unitIndex in SamuraiTopology.unitsByCell[index]) {
        if ((masks[unitIndex] & bit) != 0) return 0;
        masks[unitIndex] |= bit;
      }
    }

    var solutions = 0;

    void search() {
      if (solutions >= limit) return;
      var selectedIndex = -1;
      var selectedMask = 0;
      var selectedCount = 10;

      for (final index in SamuraiTopology.activeIndexes) {
        if (board[index] != 0) continue;
        var used = 0;
        for (final unitIndex in SamuraiTopology.unitsByCell[index]) {
          used |= masks[unitIndex];
        }
        final available = 0x1ff & ~used;
        final count = _bitCount(available);
        if (count == 0) return;
        if (count < selectedCount) {
          selectedIndex = index;
          selectedMask = available;
          selectedCount = count;
          if (count == 1) break;
        }
      }

      if (selectedIndex == -1) {
        solutions++;
        return;
      }

      var available = selectedMask;
      while (available != 0 && solutions < limit) {
        final bit = available & -available;
        available &= ~bit;
        final value = bit.bitLength;
        board[selectedIndex] = value;
        for (final unitIndex in SamuraiTopology.unitsByCell[selectedIndex]) {
          masks[unitIndex] |= bit;
        }
        search();
        for (final unitIndex in SamuraiTopology.unitsByCell[selectedIndex]) {
          masks[unitIndex] ^= bit;
        }
        board[selectedIndex] = 0;
      }
    }

    search();
    return solutions;
  }

  static int _bitCount(int value) {
    var remaining = value;
    var count = 0;
    while (remaining != 0) {
      remaining &= remaining - 1;
      count++;
    }
    return count;
  }

  static int _targetClueCount(SudokuDifficulty difficulty) =>
      switch (difficulty) {
        SudokuDifficulty.beginner => 300,
        SudokuDifficulty.easy => 270,
        SudokuDifficulty.medium => 235,
        SudokuDifficulty.hard => 200,
        SudokuDifficulty.expert => 165,
      };
}
