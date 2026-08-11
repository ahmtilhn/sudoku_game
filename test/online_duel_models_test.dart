import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/domain/sudoku_variant.dart';
import 'package:sudoku_game/services/online_duel_models.dart';

void main() {
  Map<String, dynamic> validSnapshot() => <String, dynamic>{
    'roomId': 'room-1',
    'matchId': 'match-1',
    'mode': 'ranked',
    'difficulty': 'easy',
    'status': 'active',
    'youSeat': 'A',
    'players': <String, dynamic>{
      'A': <String, dynamic>{
        'publicId': 'a',
        'username': 'alice',
        'displayName': 'Alice',
        'avatarKey': 'default',
        'ready': true,
        'screenLoaded': true,
        'connected': true,
      },
      'B': <String, dynamic>{
        'publicId': 'b',
        'username': 'bob',
        'displayName': 'Bob',
        'avatarKey': 'default',
        'ready': true,
        'screenLoaded': true,
        'connected': true,
      },
    },
    'puzzle': List<int>.filled(81, 0),
    'board': List<int>.filled(81, 0),
    'scores': <String, int>{'A': 0, 'B': 0},
    'mistakes': <String, int>{'A': 0, 'B': 0},
    'correctMoves': <String, int>{'A': 0, 'B': 0},
    'timeouts': <String, int>{'A': 0, 'B': 0},
    'currentTurnSeat': 'A',
    'turnNumber': 1,
    'turnDeadline': 2_000,
    'readyDeadline': 1_500,
    'serverTime': 1_000,
    'revision': 2,
  };

  test('legacy 81-cell payload infers classic9', () {
    final snapshot = OnlineDuelSnapshot.fromJson(validSnapshot());

    expect(snapshot.variant, same(SudokuVariant.classic9));
    expect(snapshot.boardSize, 9);
    expect(snapshot.cellCount, 81);
  });

  test('copyWith can explicitly clear nullable server fields', () {
    final snapshot = OnlineDuelSnapshot.fromJson(validSnapshot());
    final cleared = snapshot.copyWith(
      readyDeadline: null,
      turnDeadline: null,
      winnerSeat: null,
      finishReason: null,
      rating: null,
      coinSettlement: null,
    );

    expect(cleared.readyDeadline, isNull);
    expect(cleared.turnDeadline, isNull);
    expect(cleared.winnerSeat, isNull);
    expect(cleared.finishReason, isNull);
    expect(cleared.rating, isNull);
    expect(cleared.coinSettlement, isNull);
  });

  test('rejects a board whose length differs from the puzzle', () {
    final json = validSnapshot()..['board'] = List<int>.filled(80, 0);
    expect(
      () => OnlineDuelSnapshot.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects values outside the supported board range', () {
    final json = validSnapshot();
    final board = List<int>.filled(81, 0)..[20] = 10;
    json['board'] = board;
    expect(
      () => OnlineDuelSnapshot.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts a numeric classic16 payload with 256 cells', () {
    final json = validSnapshot()
      ..['variant'] = 'classic16'
      ..['boardSize'] = 16
      ..['cellCount'] = 256
      ..['puzzle'] = List<int>.filled(256, 0)
      ..['board'] = (List<int>.filled(256, 0)..[255] = 16);

    final snapshot = OnlineDuelSnapshot.fromJson(json);

    expect(snapshot.variant, same(SudokuVariant.classic16));
    expect(snapshot.boardSize, 16);
    expect(snapshot.cellCount, 256);
    expect(snapshot.board.last, 16);
  });

  test('rejects variant metadata that disagrees with puzzle length', () {
    final json = validSnapshot()
      ..['variant'] = 'classic16'
      ..['boardSize'] = 16
      ..['cellCount'] = 256;

    expect(
      () => OnlineDuelSnapshot.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects classic16 values above 16', () {
    final json = validSnapshot()
      ..['variant'] = 'classic16'
      ..['boardSize'] = 16
      ..['cellCount'] = 256
      ..['puzzle'] = List<int>.filled(256, 0)
      ..['board'] = (List<int>.filled(256, 0)..[42] = 17);

    expect(
      () => OnlineDuelSnapshot.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a board that mutates a fixed clue', () {
    final json = validSnapshot();
    final puzzle = List<int>.filled(81, 0)..[0] = 5;
    final board = List<int>.filled(81, 0)..[0] = 4;
    json['puzzle'] = puzzle;
    json['board'] = board;
    expect(
      () => OnlineDuelSnapshot.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}
