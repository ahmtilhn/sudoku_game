import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_controller.dart';
import 'package:sudoku_game/services/online_duel_emote_hub.dart';
import 'package:sudoku_game/services/online_duel_models.dart';
import 'package:sudoku_game/services/online_duel_transport.dart';

void main() {
  test('active duel sends a whitelisted emote through the transport', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();
    transport.emit(_event('snapshot', _snapshot()));
    await pumpEventQueue();

    expect(controller.sendEmote('laugh'), isTrue);
    final message = transport.sent.last;
    expect(message['type'], 'emote');
    expect((message['payload'] as Map)['emoteId'], 'laugh');

    await controller.dispose();
  });

  test('opponent emote event is exposed to the presentation hub', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();
    transport.emit(_event('snapshot', _snapshot(youSeat: 'A')));
    await pumpEventQueue();

    transport.emit(
      _event('emote', <String, dynamic>{'seat': 'B', 'emoteId': 'fire'}),
    );
    await pumpEventQueue();

    expect(OnlineDuelEmoteHub.instance.incomingEmoteId, 'fire');

    await controller.dispose();
    expect(OnlineDuelEmoteHub.instance.attached, isFalse);
  });

  test('emote sending is disabled outside an active duel', () async {
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport)..start();
    transport.emit(_event('snapshot', _snapshot(status: 'ready_window')));
    await pumpEventQueue();

    expect(controller.sendEmote('smile'), isFalse);
    expect(transport.sent.where((message) => message['type'] == 'emote'), isEmpty);

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

Map<String, dynamic> _snapshot({
  String youSeat = 'A',
  String status = 'active',
}) {
  final puzzle = List<int>.filled(81, 0)..[0] = 1;
  return <String, dynamic>{
    'roomId': 'room',
    'matchId': 'match',
    'mode': 'ranked',
    'difficulty': 'easy',
    'status': status,
    'youSeat': youSeat,
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
