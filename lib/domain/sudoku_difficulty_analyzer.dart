import 'sudoku.dart';

enum SudokuTechnique {
  nakedSingle,
  hiddenSingle,
  lockedCandidate,
  nakedPair,
  search,
}

class SudokuDifficultyAnalysis {
  const SudokuDifficultyAnalysis({
    required this.difficulty,
    required this.hardestTechnique,
    required this.logicalSteps,
    required this.searchNodes,
    required this.maxSearchDepth,
    required this.solved,
  });

  final SudokuDifficulty difficulty;
  final SudokuTechnique hardestTechnique;
  final int logicalSteps;
  final int searchNodes;
  final int maxSearchDepth;
  final bool solved;
}

class SudokuDifficultyAnalyzer {
  const SudokuDifficultyAnalyzer._();

  static SudokuDifficultyAnalysis analyze(SudokuPuzzle puzzle) {
    final board = List<int>.from(puzzle.puzzle);
    final candidates = List<int>.filled(puzzle.cellCount, 0);
    final fullMask = _fullMask(puzzle.size);
    var hardest = SudokuTechnique.nakedSingle;
    var logicalSteps = 0;

    for (var index = 0; index < board.length; index++) {
      if (board[index] == 0) {
        candidates[index] = _candidateMask(puzzle, board, index, fullMask);
      }
    }

    var progress = true;
    var contradiction = false;
    while (progress && board.any((value) => value == 0)) {
      progress = false;
      if (_propagateSolvedCells(puzzle, board, candidates)) {
        contradiction = true;
        break;
      }

      for (var index = 0; index < board.length; index++) {
        if (board[index] != 0) continue;
        final mask = candidates[index];
        if (mask == 0) {
          contradiction = true;
          break;
        }
        if (_bitCount(mask) == 1) {
          _placeValue(puzzle, board, candidates, index, _singleValue(mask));
          logicalSteps++;
          progress = true;
        }
      }
      if (contradiction || progress) continue;

      final hidden = _applyHiddenSingles(puzzle, board, candidates);
      if (hidden > 0) {
        hardest = _maxTechnique(hardest, SudokuTechnique.hiddenSingle);
        logicalSteps += hidden;
        progress = true;
        continue;
      }

      final locked = _applyLockedCandidates(puzzle, board, candidates);
      if (locked > 0) {
        hardest = _maxTechnique(hardest, SudokuTechnique.lockedCandidate);
        logicalSteps += locked;
        progress = true;
        continue;
      }

      final pairs = _applyNakedPairs(puzzle, board, candidates);
      if (pairs > 0) {
        hardest = _maxTechnique(hardest, SudokuTechnique.nakedPair);
        logicalSteps += pairs;
        progress = true;
      }
    }

    if (!contradiction && board.every((value) => value != 0)) {
      return SudokuDifficultyAnalysis(
        difficulty: switch (hardest) {
          SudokuTechnique.nakedSingle => SudokuDifficulty.beginner,
          SudokuTechnique.hiddenSingle => SudokuDifficulty.easy,
          SudokuTechnique.lockedCandidate ||
          SudokuTechnique.nakedPair => SudokuDifficulty.medium,
          SudokuTechnique.search => SudokuDifficulty.hard,
        },
        hardestTechnique: hardest,
        logicalSteps: logicalSteps,
        searchNodes: 0,
        maxSearchDepth: 0,
        solved: true,
      );
    }

    final metrics = _search(puzzle, board);
    final difficulty = !metrics.solved
        ? SudokuDifficulty.expert
        : metrics.maxDepth <= 2 && metrics.nodes <= 120
        ? SudokuDifficulty.hard
        : SudokuDifficulty.expert;
    return SudokuDifficultyAnalysis(
      difficulty: difficulty,
      hardestTechnique: SudokuTechnique.search,
      logicalSteps: logicalSteps,
      searchNodes: metrics.nodes,
      maxSearchDepth: metrics.maxDepth,
      solved: metrics.solved,
    );
  }

  static int _applyHiddenSingles(
    SudokuPuzzle puzzle,
    List<int> board,
    List<int> candidates,
  ) {
    var placements = 0;
    for (final unit in _units(puzzle)) {
      for (var value = 1; value <= puzzle.size; value++) {
        final bit = 1 << value;
        var found = -1;
        var count = 0;
        for (final index in unit) {
          if (board[index] == 0 && candidates[index] & bit != 0) {
            found = index;
            count++;
          }
        }
        if (count == 1 && found >= 0) {
          _placeValue(puzzle, board, candidates, found, value);
          placements++;
        }
      }
    }
    return placements;
  }

  static int _applyLockedCandidates(
    SudokuPuzzle puzzle,
    List<int> board,
    List<int> candidates,
  ) {
    var eliminations = 0;
    final boxesPerRow = puzzle.size ~/ puzzle.boxColumns;
    for (var box = 0; box < puzzle.size; box++) {
      final boxRow = box ~/ boxesPerRow;
      final boxColumn = box % boxesPerRow;
      final boxIndexes = <int>[];
      for (var rowOffset = 0; rowOffset < puzzle.boxRows; rowOffset++) {
        for (
          var columnOffset = 0;
          columnOffset < puzzle.boxColumns;
          columnOffset++
        ) {
          boxIndexes.add(
            (boxRow * puzzle.boxRows + rowOffset) * puzzle.size +
                boxColumn * puzzle.boxColumns +
                columnOffset,
          );
        }
      }
      for (var value = 1; value <= puzzle.size; value++) {
        final bit = 1 << value;
        final positions = boxIndexes
            .where((index) => board[index] == 0 && candidates[index] & bit != 0)
            .toList();
        if (positions.length < 2) continue;
        final rows = positions.map((index) => index ~/ puzzle.size).toSet();
        if (rows.length == 1) {
          final row = rows.single;
          for (var column = 0; column < puzzle.size; column++) {
            final index = row * puzzle.size + column;
            if (boxIndexes.contains(index) || board[index] != 0) continue;
            if (candidates[index] & bit != 0) {
              candidates[index] &= ~bit;
              eliminations++;
            }
          }
        }
        final columns = positions.map((index) => index % puzzle.size).toSet();
        if (columns.length == 1) {
          final column = columns.single;
          for (var row = 0; row < puzzle.size; row++) {
            final index = row * puzzle.size + column;
            if (boxIndexes.contains(index) || board[index] != 0) continue;
            if (candidates[index] & bit != 0) {
              candidates[index] &= ~bit;
              eliminations++;
            }
          }
        }
      }
    }
    return eliminations;
  }

  static int _applyNakedPairs(
    SudokuPuzzle puzzle,
    List<int> board,
    List<int> candidates,
  ) {
    var eliminations = 0;
    for (final unit in _units(puzzle)) {
      final pairCells = <int, List<int>>{};
      for (final index in unit) {
        if (board[index] != 0 || _bitCount(candidates[index]) != 2) continue;
        pairCells.putIfAbsent(candidates[index], () => <int>[]).add(index);
      }
      for (final entry in pairCells.entries) {
        if (entry.value.length != 2) continue;
        for (final index in unit) {
          if (entry.value.contains(index) || board[index] != 0) continue;
          final before = candidates[index];
          candidates[index] &= ~entry.key;
          if (before != candidates[index]) eliminations++;
        }
      }
    }
    return eliminations;
  }

  static bool _propagateSolvedCells(
    SudokuPuzzle puzzle,
    List<int> board,
    List<int> candidates,
  ) {
    for (var index = 0; index < board.length; index++) {
      if (board[index] != 0) continue;
      var mask = candidates[index];
      for (final peer in _peers(puzzle, index)) {
        final value = board[peer];
        if (value != 0) mask &= ~(1 << value);
      }
      candidates[index] = mask;
      if (mask == 0) return true;
    }
    return false;
  }

  static void _placeValue(
    SudokuPuzzle puzzle,
    List<int> board,
    List<int> candidates,
    int index,
    int value,
  ) {
    board[index] = value;
    candidates[index] = 0;
    final bit = 1 << value;
    for (final peer in _peers(puzzle, index)) {
      if (board[peer] == 0) candidates[peer] &= ~bit;
    }
  }

  static _SearchMetrics _search(SudokuPuzzle puzzle, List<int> source) {
    final board = List<int>.from(source);
    var nodes = 0;
    var maxDepth = 0;

    bool solve(int depth) {
      nodes++;
      if (depth > maxDepth) maxDepth = depth;
      var target = -1;
      var targetMask = 0;
      var targetCount = puzzle.size + 1;
      for (var index = 0; index < board.length; index++) {
        if (board[index] != 0) continue;
        final mask = _candidateMask(
          puzzle,
          board,
          index,
          _fullMask(puzzle.size),
        );
        final count = _bitCount(mask);
        if (count == 0) return false;
        if (count < targetCount) {
          target = index;
          targetMask = mask;
          targetCount = count;
          if (count == 1) break;
        }
      }
      if (target < 0) return true;
      for (var value = 1; value <= puzzle.size; value++) {
        if (targetMask & (1 << value) == 0) continue;
        board[target] = value;
        if (solve(depth + 1)) return true;
        board[target] = 0;
      }
      return false;
    }

    final solved = solve(0);
    return _SearchMetrics(solved: solved, nodes: nodes, maxDepth: maxDepth);
  }

  static int _candidateMask(
    SudokuPuzzle puzzle,
    List<int> board,
    int index,
    int fullMask,
  ) {
    var mask = fullMask;
    for (final peer in _peers(puzzle, index)) {
      final value = board[peer];
      if (value != 0) mask &= ~(1 << value);
    }
    return mask;
  }

  static Iterable<int> _peers(SudokuPuzzle puzzle, int index) sync* {
    final seen = <int>{};
    final row = index ~/ puzzle.size;
    final column = index % puzzle.size;
    for (var cursor = 0; cursor < puzzle.size; cursor++) {
      seen.add(row * puzzle.size + cursor);
      seen.add(cursor * puzzle.size + column);
    }
    final startRow = (row ~/ puzzle.boxRows) * puzzle.boxRows;
    final startColumn = (column ~/ puzzle.boxColumns) * puzzle.boxColumns;
    for (var rowOffset = 0; rowOffset < puzzle.boxRows; rowOffset++) {
      for (
        var columnOffset = 0;
        columnOffset < puzzle.boxColumns;
        columnOffset++
      ) {
        seen.add(
          (startRow + rowOffset) * puzzle.size + startColumn + columnOffset,
        );
      }
    }
    seen.remove(index);
    yield* seen;
  }

  static Iterable<List<int>> _units(SudokuPuzzle puzzle) sync* {
    for (var row = 0; row < puzzle.size; row++) {
      yield List<int>.generate(
        puzzle.size,
        (column) => row * puzzle.size + column,
      );
    }
    for (var column = 0; column < puzzle.size; column++) {
      yield List<int>.generate(
        puzzle.size,
        (row) => row * puzzle.size + column,
      );
    }
    final boxesPerRow = puzzle.size ~/ puzzle.boxColumns;
    for (var box = 0; box < puzzle.size; box++) {
      final boxRow = box ~/ boxesPerRow;
      final boxColumn = box % boxesPerRow;
      final indexes = <int>[];
      for (var rowOffset = 0; rowOffset < puzzle.boxRows; rowOffset++) {
        for (
          var columnOffset = 0;
          columnOffset < puzzle.boxColumns;
          columnOffset++
        ) {
          indexes.add(
            (boxRow * puzzle.boxRows + rowOffset) * puzzle.size +
                boxColumn * puzzle.boxColumns +
                columnOffset,
          );
        }
      }
      yield indexes;
    }
  }

  static int _fullMask(int size) => (1 << (size + 1)) - 2;

  static int _bitCount(int value) {
    var count = 0;
    var remaining = value;
    while (remaining != 0) {
      remaining &= remaining - 1;
      count++;
    }
    return count;
  }

  static int _singleValue(int mask) {
    for (var value = 1; value < 32; value++) {
      if (mask == 1 << value) return value;
    }
    throw StateError('Candidate mask is not a single value.');
  }

  static SudokuTechnique _maxTechnique(
    SudokuTechnique current,
    SudokuTechnique candidate,
  ) {
    return candidate.index > current.index ? candidate : current;
  }
}

class _SearchMetrics {
  const _SearchMetrics({
    required this.solved,
    required this.nodes,
    required this.maxDepth,
  });

  final bool solved;
  final int nodes;
  final int maxDepth;
}
