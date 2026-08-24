import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_controller.dart';
import 'package:sudoku_game/services/online_duel_models.dart';
import 'package:sudoku_game/services/online_duel_transport.dart';

void main() {
  test('terminal snapshot keeps rating null until backend settlement exists', () {
    final json = _snapshot(status: 'forfeited')
      ..['winnerSeat'] = 'B'
      ..['finishReason'] = 'forfeit'
      ..['rating'] = null;

    final snapshot = OnlineDuelSnapshot.fromJson(json);

    expect(snapshot.isFinished, isTrue);
    expect(snapshot.rating, isNull);
  });

  test('settled terminal snapshot exposes authoritative rating', () {
    final json = _snapshot(status: 'forfeited')
      ..['winnerSeat'] = 'B'
      ..['finishReason'] = 'forfeit'
      ..['rating'] = <String, dynamic>{
        'A': <String, int>{
          'beforeGlobal': 1000,
          'afterGlobal': 984,
          'deltaGlobal': -16,
          'beforeDifficulty': 1000,
          'afterDifficulty': 984,
          'deltaDifficulty': -16,
        },
        'B': <String, int>{
          'beforeGlobal': 1000,
          'afterGlobal': 1016,
          'deltaGlobal': 16,
          'beforeDifficulty': 1000,
          'afterDifficulty': 1016,
          'deltaDifficulty': 16,
        },
      };

    final snapshot = OnlineDuelSnapshot.fromJson(json);

    expect(snapshot.rating, isNotNull);
    expect(snapshot.rating![OnlineDuelSeat.a]!.deltaGlobal, -16);
    expect(snapshot.rating![OnlineDuelSeat.b]!.deltaGlobal, 16);
  });

  test('forfeit event marks match finished but not falsely settled', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();
    transport.emit(_event('snapshot', _snapshot()));
    await pumpEventQueue();

    transport.emit(
      _event(
        'player_forfeited',
        <String, dynamic>{
          'status': 'forfeited',
          'winnerSeat': 'B',
          'finishReason': 'forfeit',
          'scores': <String, int>{'A': 0, 'B': 10},
          'mistakes': <String, int>{'A': 0, 'B': 0},
          'correctMoves': <String, int>{'A': 0, 'B': 1},
          'timeouts': <String, int>{'A': 0, 'B': 0},
        },
        revision: 3,
      ),
    );
    await pumpEventQueue();

    expect(controller.current?.status, OnlineDuelStatus.forfeited);
    expect(controller.current?.isFinished, isTrue);
    expect(controller.current?.rating, isNull);
    expect(transport.sent.last['type'], 'request_snapshot');

    await controller.dispose();
  });
}

OnlineDuelEvent _event(
  String type,
  Map<String, dynamic> payload, {
  int revision = 2,
}) {
  return OnlineDuelEvent(
    type: type,
    revision: revision,
    serverTime: DateTime.fromMillisecondsSinceEpoch(1000),
    payload: payload,
  );
}

Map<String, dynamic> _snapshot({String status = 'active'}) {
  final puzzle = List<int>.filled(81, 0)..[0] = 1;
  return <String, dynamic>{
    'roomId': 'room',
    'matchId': 'match',
    'mode': 'ranked',
    'difficulty': 'easy',
    'status': status,
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
    'puzzle': puzzle,
    'board': puzzle,
    'scores': <String, int>{'A': 0, 'B': 0},
    'mistakes': <String, int>{'A': 0, 'B': 0},
    'correctMoves': <String, int>{'A': 0, 'B': 0},
    'timeouts': <String, int>{'A': 0, 'B': 0},
    'currentTurnSeat': 'A',
    'turnNumber': 1,
    'turnDeadline': 11000,
    'serverTime': 1000,
    'revision': 2,
  };
}
