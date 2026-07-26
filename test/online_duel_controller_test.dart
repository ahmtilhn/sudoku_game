import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_controller.dart';
import 'package:sudoku_game/services/online_duel_models.dart';
import 'package:sudoku_game/services/online_duel_transport.dart';

void main() {
  test('snapshot state is applied without requiring a solution', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();

    transport.emit(_event('snapshot', _snapshot()));
    await expectLater(
      controller.snapshots,
      emits(isA<OnlineDuelSnapshot>().having((s) => s.board[2], 'cell', 0)),
    );

    expect(controller.current?.puzzle.length, 81);
    expect(controller.current?.board.length, 81);
    await controller.dispose();
  });

  test('out of turn board is disabled at controller level', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();
    transport.emit(
      _event('snapshot', _snapshot(youSeat: 'A', currentTurnSeat: 'B')),
    );
    await pumpEventQueue();

    expect(controller.move(2, 3), isFalse);
    expect(transport.sent, isEmpty);
    await controller.dispose();
  });

  test(
    'pending move prevents a second tap until the server responds',
    () async {
      final transport = FakeOnlineDuelTransport();
      final controller = OnlineDuelController(transport)..start();
      transport.emit(_event('snapshot', _snapshot()));
      await pumpEventQueue();

      expect(controller.move(2, 3), isTrue);
      expect(controller.move(3, 4), isFalse);
      expect(transport.sent.where((m) => m['type'] == 'move'), hasLength(1));
      await controller.dispose();
    },
  );

  test('move accepted updates the local board from server event', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();
    transport.emit(_event('snapshot', _snapshot()));
    await pumpEventQueue();

    controller.move(2, 3);
    transport.emit(
      _event('move_accepted', {
        'cellIndex': 2,
        'value': 3,
        'scores': {'A': 10, 'B': 0},
      }, revision: 3),
    );
    await pumpEventQueue();

    expect(controller.current?.board[2], 3);
    expect(controller.current?.scores[OnlineDuelSeat.a], 10);
    await controller.dispose();
  });

  test('move rejected applies recovery snapshot when provided', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();
    transport.emit(_event('snapshot', _snapshot()));
    await pumpEventQueue();

    controller.move(2, 3);
    transport.emit(
      _event('move_rejected', {
        'reason': 'incorrect_value',
        'snapshot': _snapshot(board: List<int>.filled(81, 0), revision: 7),
      }, revision: 7),
    );
    await pumpEventQueue();

    expect(controller.pendingMove, isFalse);
    expect(controller.current?.revision, 7);
    await controller.dispose();
  });

  test(
    'stale revision recovery requests a fresh snapshot if none is included',
    () async {
      final transport = FakeOnlineDuelTransport();
      final controller = OnlineDuelController(transport)..start();
      transport.emit(_event('snapshot', _snapshot()));
      await pumpEventQueue();

      transport.emit(_event('protocol_error', {'code': 'stale_revision'}));
      await pumpEventQueue();

      expect(transport.sent.last['type'], 'request_snapshot');
      await controller.dispose();
    },
  );
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

Map<String, dynamic> _snapshot({
  String youSeat = 'A',
  String currentTurnSeat = 'A',
  List<int>? board,
  int revision = 2,
}) {
  final puzzle = List<int>.filled(81, 0)..[0] = 1;
  return {
    'roomId': 'room',
    'matchId': 'match',
    'mode': 'ranked',
    'difficulty': 'easy',
    'status': 'active',
    'youSeat': youSeat,
    'players': {
      'A': {
        'publicId': 'a',
        'username': 'alice',
        'displayName': 'Alice',
        'avatarKey': 'default',
        'ready': true,
        'connected': true,
      },
      'B': {
        'publicId': 'b',
        'username': 'bob',
        'displayName': 'Bob',
        'avatarKey': 'default',
        'ready': true,
        'connected': true,
      },
    },
    'puzzle': puzzle,
    'board': board ?? puzzle,
    'scores': {'A': 0, 'B': 0},
    'mistakes': {'A': 0, 'B': 0},
    'correctMoves': {'A': 0, 'B': 0},
    'timeouts': {'A': 0, 'B': 0},
    'currentTurnSeat': currentTurnSeat,
    'turnNumber': 1,
    'turnDeadline': 11000,
    'serverTime': 1000,
    'revision': revision,
  };
}
