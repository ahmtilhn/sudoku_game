import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/fantasy_sudoku_catalog.dart';
import 'package:sudoku_game/domain/sudoku.dart';
import 'package:sudoku_game/domain/sudoku_symbols.dart';

void main() {
  test('fantasy puzzle is a valid unique 16x16 Sudoku', () {
    final puzzle = FantasySudokuCatalog.puzzleForSeed(20260804);

    expect(puzzle.size, 16);
    expect(puzzle.boxRows, 4);
    expect(puzzle.boxColumns, 4);
    expect(puzzle.puzzle, hasLength(256));
    expect(puzzle.solution, hasLength(256));
    expect(SudokuEngine.isPuzzleShapeValid(puzzle), isTrue);
    expect(SudokuEngine.isComplete(puzzle, puzzle.solution), isTrue);
    expect(puzzle.puzzle.where((value) => value == 0).length, greaterThan(100));

    for (var index = 0; index < puzzle.cellCount; index++) {
      final clue = puzzle.puzzle[index];
      if (clue != 0) expect(clue, puzzle.solution[index]);
    }

    expect(_countSolutions(puzzle, limit: 2), 1);
  });

  test('fantasy seeds preserve validity and vary the board', () {
    final first = FantasySudokuCatalog.puzzleForSeed(1);
    final second = FantasySudokuCatalog.puzzleForSeed(2);

    expect(SudokuEngine.isComplete(first, first.solution), isTrue);
    expect(SudokuEngine.isComplete(second, second.solution), isTrue);
    expect(first.solution, isNot(equals(second.solution)));
  });

  test('large Sudoku symbols use 1-9 and A-G', () {
    expect(sudokuSymbol(1), '1');
    expect(sudokuSymbol(9), '9');
    expect(sudokuSymbol(10), 'A');
    expect(sudokuSymbol(16), 'G');
    expect(sudokuSymbol(0), isEmpty);
  });
}

int _countSolutions(SudokuPuzzle puzzle, {required int limit}) {
  final size = puzzle.size;
  final board = List<int>.from(puzzle.puzzle);
  final fullMask = (1 << size) - 1;
  final rowMasks = List<int>.filled(size, 0);
  final columnMasks = List<int>.filled(size, 0);
  final boxMasks = List<int>.filled(size, 0);

  int boxIndex(int row, int column) =>
      (row ~/ puzzle.boxRows) * (size ~/ puzzle.boxColumns) +
      column ~/ puzzle.boxColumns;

  for (var index = 0; index < board.length; index++) {
    final value = board[index];
    if (value == 0) continue;
    final bit = 1 << (value - 1);
    final row = index ~/ size;
    final column = index % size;
    final box = boxIndex(row, column);
    if ((rowMasks[row] & bit) != 0 ||
        (columnMasks[column] & bit) != 0 ||
        (boxMasks[box] & bit) != 0) {
      return 0;
    }
    rowMasks[row] |= bit;
    columnMasks[column] |= bit;
    boxMasks[box] |= bit;
  }

  var solutions = 0;

  void solve() {
    if (solutions >= limit) return;
    var bestIndex = -1;
    var bestMask = 0;
    var bestCount = size + 1;

    for (var index = 0; index < board.length; index++) {
      if (board[index] != 0) continue;
      final row = index ~/ size;
      final column = index % size;
      final box = boxIndex(row, column);
      final mask =
          fullMask & ~(rowMasks[row] | columnMasks[column] | boxMasks[box]);
      final count = mask.bitCount;
      if (count == 0) return;
      if (count < bestCount) {
        bestIndex = index;
        bestMask = mask;
        bestCount = count;
        if (count == 1) break;
      }
    }

    if (bestIndex < 0) {
      solutions++;
      return;
    }

    final row = bestIndex ~/ size;
    final column = bestIndex % size;
    final box = boxIndex(row, column);
    var candidates = bestMask;
    while (candidates != 0 && solutions < limit) {
      final bit = candidates & -candidates;
      candidates &= candidates - 1;
      final value = bit.bitLength;
      board[bestIndex] = value;
      rowMasks[row] |= bit;
      columnMasks[column] |= bit;
      boxMasks[box] |= bit;
      solve();
      rowMasks[row] &= ~bit;
      columnMasks[column] &= ~bit;
      boxMasks[box] &= ~bit;
      board[bestIndex] = 0;
    }
  }

  solve();
  return solutions;
}
