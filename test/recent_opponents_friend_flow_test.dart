import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friends hub lets recent opponents become friends', () {
    final source = File(
      'lib/features/social/social_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains("Tab(text: context.tr('recent_opponents'))"));
    expect(source, contains('Widget _recentOpponentsView()'));
    expect(source, contains("context.tr('recent_opponents_empty_body')"));
    expect(source, contains("_busyId == 'friend-\${player.publicId}'"));
    expect(source, contains("player.friendshipStatus != 'accepted'"));
    expect(source, contains("player.friendshipStatus != 'pending'"));
    expect(source, contains("context.tr('add_friend')"));
    expect(source, contains('onPrimary: () => _sendFriendRequest(player)'));
  });

  test('recent opponents endpoint returns friendship status', () {
    final source = File(
      'backend/social_worker/src/index.ts',
    ).readAsStringSync();
    final start = source.indexOf('async function listRecentOpponents');
    final end = source.indexOf('async function createChallenge', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final recentOpponents = source.substring(start, end);
    expect(recentOpponents, contains('AS friendship_status'));
    expect(recentOpponents, contains('FROM friendships f'));
    expect(recentOpponents, contains('r.last_played_at'));
    expect(recentOpponents, contains('rows.results.map(playerJson)'));
  });
}
