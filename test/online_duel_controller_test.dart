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
        'seat': 'A',
        'forYou': true,
        'cellIndex': 2,
        'value': 3,
        'scores': {'A': 10, 'B': 0},
      }, revision: 3),
    );
    await pumpEventQueue();

    expect(controller.current?.board[2], 3);
    expect(controller.current?.scores[OnlineDuelSeat.a], 10);
    expect(controller.pendingMove, isFalse);
    await controller.dispose();
  });

  test('game_started applies active board without manual refresh', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();

    transport.emit(
      _event('game_started', _snapshot(status: 'active'), revision: 4),
    );
    await pumpEventQueue();

    expect(controller.current?.status, OnlineDuelStatus.active);
    expect(controller.current?.isLocalTurn, isTrue);
    expect(controller.move(2, 3), isTrue);
    await controller.dispose();
  });

  test('screen loaded sends the backend loaded event', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();

    controller.screenLoaded();

    expect(transport.sent.single['type'], 'game_screen_loaded');
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

  test('rejected move emits feedback and clears pending state', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();
    final feedback = expectLater(
      controller.feedback,
      emits(
        isA<OnlineDuelFeedback>().having(
          (f) => f.message,
          'message',
          'Sıra sende değil.',
        ),
      ),
    );
    transport.emit(_event('snapshot', _snapshot()));
    await pumpEventQueue();

    controller.move(2, 3);
    transport.emit(_event('move_rejected', {'reason': 'not_your_turn'}));
    await feedback;

    expect(controller.pendingMove, isFalse);
    expect(transport.sent.last['type'], 'request_snapshot');
    await controller.dispose();
  });

  test(
    'opponent rejected move does not emit local feedback or change local seat',
    () async {
      final transport = FakeOnlineDuelTransport();
      final controller = OnlineDuelController(transport)..start();
      final receivedFeedback = <OnlineDuelFeedback>[];
      final feedbackSubscription = controller.feedback.listen(
        receivedFeedback.add,
      );

      transport.emit(
        _event('snapshot', _snapshot(youSeat: 'A', currentTurnSeat: 'B')),
      );
      await pumpEventQueue();

      transport.emit(
        _event('move_rejected', {
          'seat': 'B',
          'forYou': false,
          'reason': 'incorrect_value',
          'snapshot': _snapshot(
            youSeat: 'A',
            currentTurnSeat: 'A',
            revision: 7,
          ),
        }, revision: 7),
      );
      await pumpEventQueue();

      expect(receivedFeedback, isEmpty);
      expect(controller.current?.youSeat, OnlineDuelSeat.a);
      expect(controller.current?.isLocalTurn, isTrue);
      expect(controller.current?.revision, 7);

      await feedbackSubscription.cancel();
      await controller.dispose();
    },
  );

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
  String status = 'active',
  List<int>? board,
  int revision = 2,
}) {
  final puzzle = List<int>.filled(81, 0)..[0] = 1;
  return {
    'roomId': 'room',
    'matchId': 'match',
    'mode': 'ranked',
    'difficulty': 'easy',
    'status': status,
    'youSeat': youSeat,
    'players': {
      'A': {
        'publicId': 'a',
        'username': 'alice',
        'displayName': 'Alice',
        'avatarKey': 'default',
        'ready': true,
        'screenLoaded': true,
        'connected': true,
      },
      'B': {
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
