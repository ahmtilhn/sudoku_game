import 'dart:io';

import 'package:sudoku_game/features/social/challenge_navigation_gate.dart';
import 'package:sudoku_game/services/social_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('challenge push gate ignores stale invitations before opening UI', () {
    final now = DateTime.utc(2026, 8, 24, 12);
    final pending = _challenge(
      status: 'pending',
      expiresAt: now.add(const Duration(minutes: 2)),
    );
    final expired = _challenge(
      status: 'pending',
      expiresAt: now.subtract(const Duration(seconds: 1)),
    );
    final declined = _challenge(
      status: 'declined',
      expiresAt: now.add(const Duration(minutes: 2)),
    );
    final accepted = _challenge(
      status: 'accepted',
      expiresAt: now.subtract(const Duration(minutes: 5)),
      roomId: 'room-1',
    );

    expect(challengePushCanOpen(pending, now), isTrue);
    expect(challengePushCanOpen(expired, now), isFalse);
    expect(challengePushCanOpen(declined, now), isFalse);
    expect(challengePushCanOpen(accepted, now), isTrue);
  });

  test('modern home mounts a non-interrupting global push gate', () {
    final shell = File(
      'lib/features/home/main_experience_shell.dart',
    ).readAsStringSync();
    final gate = File(
      'lib/features/home/push_room_navigation_gate.dart',
    ).readAsStringSync();
    final challengeGate = File(
      'lib/features/social/challenge_navigation_gate.dart',
    ).readAsStringSync();

    expect(shell, contains('PushRoomNavigationGate('));
    expect(gate, contains('_push.initialize()'));
    expect(gate, contains('PreMatchReadyScreen(roomId: roomId)'));
    expect(gate, contains('RematchInvitationScreen('));
    expect(gate, contains('SocialHubScreen()'));
    expect(gate, contains('ModalRoute.of(context)?.isCurrent'));
    expect(gate, isNot(contains('openedChallengeId.addListener')));
    expect(gate, isNot(contains('UxChallengeInvitationScreen(')));

    expect(challengeGate, contains('openedChallengeId.addListener'));
    expect(challengeGate, contains('ChallengeInvitationScreen('));
    expect(challengeGate, contains('ModalRoute.of(context)?.isCurrent'));
    expect(challengeGate, contains('_challengeOpenScheduled'));
    expect(challengeGate, contains('_social.loadChallenge(challengeId)'));
    expect(challengeGate, contains('challengePushCanOpen(challenge'));
  });

  test('outgoing direct challenge opens and owns a waiting flow', () {
    final hub = File(
      'lib/features/social/social_hub_screen.dart',
    ).readAsStringSync();
    final waiting = File(
      'lib/features/social/challenge_waiting_screen.dart',
    ).readAsStringSync();

    expect(hub, contains('final challenge = await _social.createChallenge('));
    expect(hub, contains('ChallengeWaitingScreen(challenge: challenge)'));
    expect(waiting, contains('_social.loadChallenge(widget.challenge.id)'));
    expect(waiting, contains('_social.cancelChallenge(widget.challenge.id)'));
    expect(waiting, contains('PreMatchReadyScreen(roomId: roomId)'));
  });

  test('friend request writes are wrapped with push notifications', () {
    final entry = File(
      'backend/social_worker/src/entry_v2.ts',
    ).readAsStringSync();
    final friendPush = File(
      'backend/social_worker/src/friend_notifications.ts',
    ).readAsStringSync();

    expect(entry, contains('handleFriendNotificationRequest'));
    expect(entry, contains('isFriendNotificationRoute'));
    expect(friendPush, contains("type: 'friend_request'"));
    expect(friendPush, contains("type: 'friend_response'"));
    expect(friendPush, contains('sendPlayerPush'));
  });

  test('push destinations persist until a navigation gate consumes them', () {
    final push = File(
      'lib/services/push_notification_service.dart',
    ).readAsStringSync();

    expect(push, isNot(contains('_ConsumableValueNotifier')));
    expect(push, contains('openedChallengeId = ValueNotifier<String?>(null)'));
    expect(push, contains('openedRematchId = ValueNotifier<String?>(null)'));
    expect(push, contains('openedSocialId = ValueNotifier<String?>(null)'));
  });

  test(
    'foreground challenge becomes a phone notification when UI is deferred',
    () {
      final push = File(
        'lib/services/push_notification_service.dart',
      ).readAsStringSync();

      expect(push, contains('setForegroundNotificationPresentationOptions('));
      expect(push, contains('alert: false'));
      expect(push, contains('sound: false'));
      expect(push, contains('_handleForegroundMessage'));
      expect(push, contains('_showForegroundSystemNotification'));
      expect(push, contains('AndroidNotificationDetails('));
      expect(push, contains('DarwinNotificationDetails('));
    },
  );
}

SocialChallenge _challenge({
  required String status,
  required DateTime expiresAt,
  String? roomId,
}) {
  return SocialChallenge(
    id: 'challenge-$status',
    difficulty: 'easy',
    status: status,
    challenger: _player('challenger'),
    recipient: _player('recipient'),
    expiresAt: expiresAt,
    roomId: roomId,
  );
}

SocialPlayer _player(String id) {
  return SocialPlayer(
    publicId: id,
    username: id,
    displayName: id,
    rating: 1000,
    gamesPlayed: 0,
    wins: 0,
    achievementCount: 0,
  );
}
