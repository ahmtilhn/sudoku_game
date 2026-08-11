import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'accepted challenge responses are idempotent and require funded rooms',
    () {
      final worker = File(
        'backend/social_worker/src/index.ts',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(worker, contains("if (challenge.status === 'accepted')"));
      expect(worker, contains('ensureAcceptedChallengeMatch(env, challenge)'));
      expect(
        worker,
        contains(
          "WHERE (challenger_id = ? OR recipient_id = ?)\n         AND status = 'accepted'",
        ),
      );
      expect(worker, contains("funded?.status !== 'funded'"));
      expect(
        worker,
        contains('The accepted challenge room is no longer playable.'),
      );
      expect(
        worker,
        contains('Both players need enough Coin to create the challenge room.'),
      );
    },
  );

  test('challenge accept UI recovers only its authoritative active room', () {
    final invitation = File(
      'lib/features/social/ux_challenge_invitation_screen.dart',
    ).readAsStringSync();

    expect(invitation, contains('_recoverAcceptedChallenge()'));
    expect(
      invitation,
      contains('for (var attempt = 0; attempt < 12; attempt++)'),
    );
    expect(invitation, contains('activeChallengeId == widget.challengeId'));
    expect(invitation, contains('await _openRoom(roomId)'));
  });

  test('pre-match room automatically retries an initial socket failure', () {
    final preMatch = File(
      'lib/features/duel/pre_match_ready_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(preMatch, contains('Timer? _retryTimer;'));
    expect(preMatch, contains('void _scheduleReconnect()'));
    expect(preMatch, contains('_scheduleReconnect();'));
  });
}
