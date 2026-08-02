import 'package:flutter_test/flutter_test.dart';
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
