import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/domain/samurai_sudoku.dart';
import 'package:sudoku_game/domain/sudoku.dart';
import 'package:sudoku_game/domain/sudoku_variant.dart';
import 'package:sudoku_game/services/online_duel_models.dart';

void main() {
  test('parses a valid 441-cell Samurai online snapshot', () {
    final generated = SamuraiEngine.generate(
      difficulty: SudokuDifficulty.beginner,
      seed: 5021,
    );
    final snapshot = OnlineDuelSnapshot.fromJson(
      _snapshotJson(
        puzzle: generated.puzzle,
        board: generated.puzzle,
        variant: 'samurai',
      ),
    );

    expect(snapshot.variant, 'samurai');
    expect(snapshot.puzzle, hasLength(SamuraiTopology.canvasCellCount));
    expect(snapshot.board, hasLength(SamuraiTopology.canvasCellCount));
    expect(
      snapshot.puzzle.where((value) => value == SamuraiTopology.inactiveCell),
      hasLength(72),
    );
  });

  test('rejects a Samurai snapshot whose inactive mask changed', () {
    final generated = SamuraiEngine.generate(
      difficulty: SudokuDifficulty.beginner,
      seed: 5022,
    );
    final board = List<int>.from(generated.puzzle);
    final inactiveIndex = List<int>.generate(
      SamuraiTopology.canvasCellCount,
      (index) => index,
    ).firstWhere((index) => !SamuraiTopology.isActiveIndex(index));
    board[inactiveIndex] = 0;

    expect(
      () => OnlineDuelSnapshot.fromJson(
        _snapshotJson(
          puzzle: generated.puzzle,
          board: board,
          variant: 'samurai',
        ),
      ),
      throwsFormatException,
    );
  });

  test('keeps old online snapshots classic when variant is absent', () {
    final puzzle = List<int>.filled(81, 0);
    final json = _snapshotJson(puzzle: puzzle, board: puzzle);
    json.remove('variant');

    final snapshot = OnlineDuelSnapshot.fromJson(json);

    expect(snapshot.variant, same(SudokuVariant.classic9));
    expect(snapshot.board, hasLength(81));
  });
}

Map<String, dynamic> _snapshotJson({
  required List<int> puzzle,
  required List<int> board,
  String variant = 'classic',
}) {
  const player = <String, dynamic>{
    'publicId': 'PLAYER',
    'username': 'player',
    'displayName': 'Player',
    'avatarKey': 'default',
    'ready': true,
    'screenLoaded': true,
    'connected': true,
  };
  return <String, dynamic>{
    'roomId': 'room',
    'matchId': 'match',
    'mode': 'ranked',
    'variant': variant,
    'difficulty': 'beginner',
    'status': 'active',
    'youSeat': 'A',
    'players': <String, dynamic>{'A': player, 'B': player},
    'puzzle': puzzle,
    'board': board,
    'scores': <String, int>{'A': 0, 'B': 0},
    'mistakes': <String, int>{'A': 0, 'B': 0},
    'correctMoves': <String, int>{'A': 0, 'B': 0},
    'timeouts': <String, int>{'A': 0, 'B': 0},
    'currentTurnSeat': 'A',
    'turnNumber': 1,
    'serverTime': DateTime.now().millisecondsSinceEpoch,
    'revision': 1,
  };
}
