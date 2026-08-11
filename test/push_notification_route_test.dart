import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/push_notification_service.dart';

void main() {
  test('accepted challenge response routes to the ready room', () {
    final target = parsePushNotificationDestination(<String, dynamic>{
      'type': 'challenge_response',
      'challengeId': 'challenge-1',
      'status': 'accepted',
      'roomId': 'room-42',
    });

    expect(target, isNotNull);
    expect(target!.type, PushNotificationDestinationType.room);
    expect(target.id, 'room-42');
    expect(target.payload, 'room:room-42');
  });

  test('declined challenge response stays informational', () {
    final target = parsePushNotificationDestination(<String, dynamic>{
      'type': 'challenge_response',
      'challengeId': 'challenge-2',
      'status': 'declined',
      'roomId': '',
    });

    expect(target, isNotNull);
    expect(target!.type, PushNotificationDestinationType.informational);
    expect(target.id, 'challenge-2');
  });

  test('new challenge opens the invitation flow', () {
    final target = parsePushNotificationDestination(<String, dynamic>{
      'type': 'challenge',
      'challengeId': 'challenge-3',
    });

    expect(target, isNotNull);
    expect(target!.type, PushNotificationDestinationType.challenge);
    expect(target.id, 'challenge-3');
  });

  test('rematch payload opens the rematch flow', () {
    final target = parsePushNotificationDestination(<String, dynamic>{
      'type': 'rematch',
      'rematchId': 'rematch-9',
    });

    expect(target, isNotNull);
    expect(target!.type, PushNotificationDestinationType.rematch);
    expect(target.id, 'rematch-9');
  });
}
