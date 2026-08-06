import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sudoku_game/data/samurai_game_session_store.dart';
import 'package:sudoku_game/domain/samurai_sudoku.dart';
import 'package:sudoku_game/domain/sudoku.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Samurai session survives a storage round trip', () async {
    final puzzle = SamuraiEngine.generate(
      difficulty: SudokuDifficulty.beginner,
      seed: 711,
    );
    final board = List<int>.from(puzzle.puzzle);
    final editable = SamuraiTopology.activeIndexes.firstWhere(
      (index) => board[index] == 0,
    );
    board[editable] = puzzle.solution[editable];
    final session = SamuraiGameSession(
      puzzle: puzzle,
      board: board,
      notes: <int, Set<int>>{
        SamuraiTopology.activeIndexes.firstWhere(
          (index) => board[index] == 0,
        ): <int>{1, 2, 3},
      },
      hintedIndexes: <int>{editable},
      elapsedSeconds: 91,
      mistakes: 1,
      hintsUsed: 1,
      notesMode: true,
      updatedAt: DateTime.utc(2026, 8, 5, 19, 0),
    );

    await SamuraiGameSessionStore.instance.save(session);
    SamuraiGameSessionStore.instance.activeSession.value = null;
    await SamuraiGameSessionStore.instance.initialize();

    final restored = SamuraiGameSessionStore.instance.activeSession.value;
    expect(restored, isNotNull);
    expect(restored!.puzzle.id, puzzle.id);
    expect(restored.board, board);
    expect(restored.hintedIndexes, <int>{editable});
    expect(restored.elapsedSeconds, 91);
    expect(restored.mistakes, 1);
    expect(restored.hintsUsed, 1);
    expect(restored.notesMode, isTrue);
  });

  test('corrupt Samurai session is discarded', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_samurai_game_session_v1': '{"version":1,"board":[4]}',
    });

    await SamuraiGameSessionStore.instance.initialize();

    expect(SamuraiGameSessionStore.instance.activeSession.value, isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey('active_samurai_game_session_v1'),
      isFalse,
    );
  });
}
