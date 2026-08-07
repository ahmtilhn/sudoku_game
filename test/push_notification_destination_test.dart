import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/push_notification_service.dart';

void main() {
  test('challenge push opens the invitation destination', () {
    final destination = parsePushNotificationDestination(<String, dynamic>{
      'type': 'challenge',
      'challengeId': 'challenge-123',
      'difficulty': 'hard',
      'variant': 'classic16',
    });

    expect(destination, isNotNull);
    expect(destination!.type, PushNotificationDestinationType.challenge);
    expect(destination.id, 'challenge-123');
    expect(destination.payload, 'challenge:challenge-123');
  });

  test('accepted challenge push opens the ready room', () {
    final destination = parsePushNotificationDestination(<String, dynamic>{
      'type': 'challenge_response',
      'challengeId': 'challenge-123',
      'status': 'accepted',
      'roomId': 'classic16:room-123',
    });

    expect(destination, isNotNull);
    expect(destination!.type, PushNotificationDestinationType.room);
    expect(destination.id, 'classic16:room-123');
    expect(destination.payload, 'room:classic16:room-123');
  });
}
