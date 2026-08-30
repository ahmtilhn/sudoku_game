import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friends hub treats incoming pending as accept-or-decline', () {
    final source = File(
      'lib/features/social/social_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains("p.friendshipStatus != 'incoming_pending'"));
    expect(source, contains("p.friendshipStatus == 'incoming_pending'"));
    expect(source, contains('_respondRequest(p, true)'));
    expect(source, contains('_respondRequest(p, false)'));
    expect(source, contains('await _findPlayers();'));
  });

  test('legacy platform screen cannot resend pending relationships', () {
    final source = File(
      'lib/features/social/platform_social_screen.dart',
    ).readAsStringSync();

    expect(source, contains("player.friendshipStatus != 'pending'"));
    expect(source, contains("player.friendshipStatus != 'outgoing_pending'"));
    expect(source, contains("player.friendshipStatus != 'incoming_pending'"));
    expect(source, contains('_friendRequestsInFlight.contains(id)'));
  });

  test('post-game add friend waits for relationship lookup', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();

    expect(source, contains('bool _friendshipStatusLoading = true;'));
    expect(source, contains('!_friendshipStatusLoading &&'));
    expect(source, contains("_friendshipStatus != 'outgoing_pending'"));
    expect(source, contains("_friendshipStatus != 'incoming_pending'"));
    expect(source, contains('_friendshipStatusLoading = false'));
  });

  test(
    'production entry routes friendship reads and writes through hardening',
    () {
      final source = File(
        'backend/social_worker/src/entry_v2.ts',
      ).readAsStringSync();
      final friendSource = File(
        'backend/social_worker/src/friend_notifications.ts',
      ).readAsStringSync();

      expect(source, contains("request.method !== 'OPTIONS'"));
      expect(friendSource, contains("pathname === '/v1/players/search'"));
      expect(friendSource, contains("pathname === '/v1/opponents/recent'"));
      expect(friendSource, contains("WHERE friendships.status = 'declined'"));
      expect(friendSource, contains("code: 'already_friends'"));
      expect(friendSource, contains("code: 'friend_request_already_pending'"));
      expect(friendSource, contains("code: 'incoming_friend_request_pending'"));
      expect(friendSource, contains("AND b.status = 'blocked'"));
    },
  );
}
