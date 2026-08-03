import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepted challenge responses are idempotent and repair room rows', () {
    final worker = File(
      'backend/social_worker/src/index.ts',
    ).readAsStringSync();

    expect(
      worker,
      contains("challenge.status !== 'pending' && challenge.status !== 'accepted'"),
    );
    expect(worker, contains('ensureAcceptedChallengeMatch(env, accepted)'));
    expect(
      worker,
      contains("WHERE (challenger_id = ? OR recipient_id = ?)\n         AND status = 'accepted'"),
    );
    expect(
      worker,
      contains("Unable to create the accepted challenge room."),
    );
  });

  test('challenge accept UI recovers an authoritative active room', () {
    final invitation = File(
      'lib/features/social/ux_challenge_invitation_screen.dart',
    ).readAsStringSync();

    expect(invitation, contains('_recoverAcceptedChallenge()'));
    expect(invitation, contains('for (var attempt = 0; attempt < 12; attempt++)'));
    expect(invitation, contains('await _openRoom(roomId)'));
  });

  test('pre-match room automatically retries an initial socket failure', () {
    final preMatch = File(
      'lib/features/duel/pre_match_ready_screen.dart',
    ).readAsStringSync();

    expect(preMatch, contains('Timer? _retryTimer;'));
    expect(preMatch, contains('void _scheduleReconnect()'));
    expect(preMatch, contains('_scheduleReconnect();'));
  });
}
