from __future__ import annotations

from pathlib import Path
import runpy
import textwrap

runpy.run_path("tool/apply_friendship_state_hardening_v2.py", run_name="__main__")

Path("test/recent_opponents_friend_flow_test.dart").write_text(
    textwrap.dedent(
        '''\
        import 'dart:io';

        import 'package:flutter_test/flutter_test.dart';

        void main() {
          test('friends hub lets recent opponents use directional friendship actions', () {
            final source = File(
              'lib/features/social/social_hub_screen.dart',
            ).readAsStringSync();

            expect(source, contains('Widget _recentView()'));
            expect(source, contains("context.tr('recent_opponents_empty_body')"));
            expect(source, contains("p.friendshipStatus == 'incoming_pending'"));
            expect(source, contains("p.friendshipStatus != 'outgoing_pending'"));
            expect(source, contains("p.friendshipStatus != 'incoming_pending'"));
            expect(source, contains('_respondRequest(p, true)'));
            expect(source, contains('_respondRequest(p, false)'));
            expect(source, contains('_sendFriendRequest(p)'));
          });

          test('production recent opponents endpoint returns directional friendship status', () {
            final entry = File(
              'backend/social_worker/src/entry_v2.ts',
            ).readAsStringSync();
            final source = File(
              'backend/social_worker/src/friend_notifications.ts',
            ).readAsStringSync();
            final start = source.indexOf('async function handleRecentOpponents');
            final end = source.indexOf('function playerJson', start);

            expect(entry, contains("isFriendNotificationRoute(url.pathname)"));
            expect(start, greaterThanOrEqualTo(0));
            expect(end, greaterThan(start));
            final recentOpponents = source.substring(start, end);
            expect(recentOpponents, contains("'outgoing_pending'"));
            expect(recentOpponents, contains("'incoming_pending'"));
            expect(recentOpponents, contains("f.status = 'accepted'"));
            expect(recentOpponents, contains("b.status = 'blocked'"));
            expect(recentOpponents, contains('r.last_played_at'));
            expect(recentOpponents, contains('rows.results.map(playerJson)'));
          });
        }
        '''
    ),
    encoding="utf-8",
)

print("Friendship state hardening v3 patch applied successfully.")
