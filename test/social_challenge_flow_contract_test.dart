import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('modern home mounts the global push navigation gate', () {
    final shell = File(
      'lib/features/home/main_experience_shell.dart',
    ).readAsStringSync();
    final gate = File(
      'lib/features/home/push_room_navigation_gate.dart',
    ).readAsStringSync();

    expect(shell, contains('PushRoomNavigationGate('));
    expect(gate, contains('_push.initialize()'));
    expect(gate, contains('PreMatchReadyScreen(roomId: roomId)'));
    expect(gate, contains('UxChallengeInvitationScreen('));
    expect(gate, contains('RematchInvitationScreen('));
    expect(gate, contains('SocialHubScreen()'));
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
}
