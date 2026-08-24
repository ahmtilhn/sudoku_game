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

  test('rematch push opens the rematch invitation destination', () {
    final destination = parsePushNotificationDestination(<String, dynamic>{
      'type': 'rematch_invitation',
      'rematchId': 'rematch-123',
      'previousMatchId': 'match-9',
    });

    expect(destination, isNotNull);
    expect(destination!.type, PushNotificationDestinationType.rematch);
    expect(destination.id, 'rematch-123');
    expect(destination.payload, 'rematch:rematch-123');
  });

  test('friend request push opens the social destination', () {
    final destination = parsePushNotificationDestination(<String, dynamic>{
      'type': 'friend_request',
      'requesterPublicId': 'PLAYER1234',
    });

    expect(destination, isNotNull);
    expect(destination!.type, PushNotificationDestinationType.social);
    expect(destination.id, 'PLAYER1234');
    expect(destination.payload, 'social:PLAYER1234');
  });

  test('friend response push opens the social destination', () {
    final destination = parsePushNotificationDestination(<String, dynamic>{
      'type': 'friend_response',
      'status': 'accepted',
      'playerPublicId': 'PLAYER5678',
    });

    expect(destination, isNotNull);
    expect(destination!.type, PushNotificationDestinationType.social);
    expect(destination.id, 'PLAYER5678');
  });
}
