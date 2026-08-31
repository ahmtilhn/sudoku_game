import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online duel has a local 30 second disconnect escape hatch', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();
    expect(source, contains('Duration(seconds: 30)'));
    expect(source, contains('_disconnectEscapeTimer'));
    expect(
      source,
      contains('Navigator.of(context).popUntil((route) => route.isFirst)'),
    );
    expect(source, contains('snapshot.status == OnlineDuelStatus.paused'));
    expect(source, contains('_localConnectionInterrupted'));
  });

  test(
    'forfeit waits for the authoritative result and keeps result visible',
    () {
      final source = File(
        'lib/features/duel/online_duel_screen.dart',
      ).readAsStringSync();
      expect(source, contains('await _submitForfeitAndWaitForResult()'));
      expect(source, contains('waitForAuthoritativeResult'));
      expect(source, contains('setState(() => _forfeiting = true)'));
      expect(source, contains('_showResultOnce(snapshot);'));
      expect(source, contains('_showResultOnce(finished);'));
      expect(
        source,
        isNot(contains('if (mounted) Navigator.of(context).popUntil')),
      );
      expect(
        source,
        isNot(
          contains(
            'await Future<void>.delayed(const Duration(milliseconds: 180))',
          ),
        ),
      );
    },
  );

  test('result sheet is resilient while waiting for settlement', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();
    expect(source, contains('_settlementWaitMatchId'));
    expect(source, contains('_settlementWaitMatchId != snapshot.matchId'));
    expect(source, contains('Result economy refresh unavailable'));
    expect(source, contains('showModalBottomSheet<String>'));
  });

  test(
    'rank result sheet surfaces promotion rewards from settlement payload',
    () {
      final source = File(
        'lib/features/duel/online_duel_screen.dart',
      ).readAsStringSync();
      expect(source, contains('value.rankUp || value.rewardCoins > 0'));
      expect(source, contains('result.rewards'));
      expect(source, contains('DuelAssetIcon(DuelAsset.coin'));
      expect(source, contains("context.tr('coin_reward_value'"));
    },
  );

  test(
    'result actions route to main menu or online duel selection directly',
    () {
      final source = File(
        'lib/features/duel/online_duel_screen.dart',
      ).readAsStringSync();
      expect(source, contains("action == 'new_match'"));
      expect(source, contains('pushAndRemoveUntil<void>'));
      expect(source, contains('const MatchmakingScreen()'));
      expect(
        source,
        contains('Navigator.of(context).popUntil((route) => route.isFirst)'),
      );
      expect(source, isNot(contains('Navigator.of(context).pop(action)')));
    },
  );

  test('arena identity and score layout uses inward large score placement', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();
    expect(source, contains('class _HeaderPlayer extends StatelessWidget'));
    expect(source, contains('final score = snapshot.scores[seat] ?? 0'));
    expect(source, contains("context.tr('rp_signed_value'"));
    expect(source, contains("score > 0 ? '+' : ''"));
    expect(
      source,
      contains(
        'textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr',
      ),
    );
    expect(
      source,
      contains('children: [avatar, const SizedBox(width: 7), info]'),
    );
  });

  test('all challenge acceptance paths converge on pre-match ready', () {
    final legacy = File(
      'lib/features/social/challenge_invitation_screen.dart',
    ).readAsStringSync();
    final modern = File(
      'lib/features/social/ux_challenge_invitation_screen.dart',
    ).readAsStringSync();
    final waiting = File(
      'lib/features/social/challenge_waiting_screen.dart',
    ).readAsStringSync();
    expect(legacy, contains('PreMatchReadyScreen(roomId: roomId)'));
    expect(legacy, isNot(contains('OnlineDuelScreen(roomId: roomId)')));
    expect(modern, contains('Future<void> _openRoom(String roomId)'));
    expect(waiting, contains('unawaited(_openRoom(roomId))'));
  });

  test('rematch acceptance creates a fresh ready-room id', () {
    final main = File('backend/social_worker/src/main.ts').readAsStringSync();
    expect(main, contains('roomIdForVariant(variant, crypto.randomUUID())'));
    expect(
      main,
      contains('markRematchStatus(env, invitation.id, \'accepted\', roomId)'),
    );
  });
}
