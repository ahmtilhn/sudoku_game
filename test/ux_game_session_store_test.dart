import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/ux_game_session_store.dart';
import 'package:sudoku_game/domain/sudoku.dart';

void main() {
  test('full puzzle session round-trips and validates', () {
    final puzzle = SudokuEngine.generate(
      difficulty: SudokuDifficulty.easy,
      seed: 4242,
      id: 'career-random-easy-4242',
    );
    final session = UxGameSession(
      puzzle: puzzle,
      board: List<int>.from(puzzle.puzzle),
      notes: const <int, Set<int>>{},
      history: const <UxSessionMove>[],
      hintedIndexes: const <int>{},
      selectedIndex: null,
      elapsedSeconds: 12,
      mistakes: 0,
      totalMistakes: 0,
      hintsUsed: 0,
      notesMode: false,
      roundLost: false,
      savedAt: DateTime.utc(2026, 8, 3),
    );

    final decoded = UxGameSession.fromJson(session.toJson());

    expect(decoded.isValid, isTrue);
    expect(decoded.puzzle.id, puzzle.id);
    expect(decoded.puzzle.puzzle, puzzle.puzzle);
    expect(decoded.puzzle.solution, puzzle.solution);
    expect(decoded.elapsedSeconds, 12);
    expect(decoded.mode, 'practice');
  });

  test('invalid solved value is rejected', () {
    final puzzle = SudokuEngine.generate(
      difficulty: SudokuDifficulty.beginner,
      seed: 73,
      id: 'daily-73',
    );
    final board = List<int>.from(puzzle.puzzle);
    final empty = board.indexOf(0);
    board[empty] = puzzle.solution[empty] == 1 ? 2 : 1;
    final session = UxGameSession(
      puzzle: puzzle,
      board: board,
      notes: const <int, Set<int>>{},
      history: const <UxSessionMove>[],
      hintedIndexes: const <int>{},
      selectedIndex: empty,
      elapsedSeconds: 0,
      mistakes: 0,
      totalMistakes: 0,
      hintsUsed: 0,
      notesMode: false,
      roundLost: false,
      savedAt: DateTime.utc(2026, 8, 3),
    );

    expect(session.isValid, isFalse);
  });
}
