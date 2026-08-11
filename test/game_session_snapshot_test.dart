import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/game_session_store.dart';
import 'package:sudoku_game/domain/sudoku.dart';

void main() {
  const puzzle = SudokuPuzzle(
    id: 'session-test',
    difficulty: SudokuDifficulty.easy,
    puzzle: <int>[1, 0, 0, 4, 0, 4, 1, 0, 0, 1, 4, 0, 4, 0, 0, 1],
    solution: <int>[1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
    size: 4,
    boxRows: 2,
    boxColumns: 2,
  );

  GameSessionSnapshot snapshot({
    List<int>? board,
    Map<int, Set<int>>? notes,
    String? signature,
  }) {
    return GameSessionSnapshot(
      puzzleId: puzzle.id,
      puzzleSignature: signature ?? GameSessionSnapshot.signatureFor(puzzle),
      board: board ?? List<int>.from(puzzle.puzzle),
      notes:
          notes ??
          <int, Set<int>>{
            1: <int>{2, 3},
          },
      history: const <GameSessionMove>[],
      hintedIndexes: const <int>{},
      selectedIndex: 1,
      elapsedSeconds: 12,
      mistakes: 1,
      totalMistakes: 1,
      hintsUsed: 0,
      notesMode: true,
      roundLost: false,
      savedAt: DateTime.utc(2026, 8, 2),
    );
  }

  test('accepts a valid resumable session', () {
    expect(snapshot().isValidFor(puzzle), isTrue);
  });

  test('rejects a session that changes a fixed clue', () {
    final board = List<int>.from(puzzle.puzzle)..[0] = 2;
    expect(snapshot(board: board).isValidFor(puzzle), isFalse);
  });

  test('rejects a session with a value outside the verified solution', () {
    final board = List<int>.from(puzzle.puzzle)..[1] = 4;
    expect(snapshot(board: board).isValidFor(puzzle), isFalse);
  });

  test('rejects notes on fixed or completed cells', () {
    expect(
      snapshot(
        notes: <int, Set<int>>{
          0: <int>{2},
        },
      ).isValidFor(puzzle),
      isFalse,
    );
  });

  test('rejects a session saved for a different puzzle revision', () {
    expect(snapshot(signature: 'stale-signature').isValidFor(puzzle), isFalse);
  });
}
