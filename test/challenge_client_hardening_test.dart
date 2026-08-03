import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // This suite also guards the combined PR #38 + latest-main challenge flow.
  test('challenge polling is exact and challenge-aware', () {
    final waiting = File(
      'lib/features/social/challenge_waiting_screen.dart',
    ).readAsStringSync();
    final invitation = File(
      'lib/features/social/ux_challenge_invitation_screen.dart',
    ).readAsStringSync();
    final api = File(
      'lib/services/social_api_client.dart',
    ).readAsStringSync();

    expect(api, contains('Future<SocialChallenge> loadChallenge'));
    expect(api, contains('Future<SocialChallenge> cancelChallenge'));
    expect(waiting, contains('activeChallengeId == challenge.id'));
    expect(invitation, contains('activeChallengeId == widget.challengeId'));
  });

  test('online duel exposes surrender and waits for settlement', () {
    final duel = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();
    final prematch = File(
      'lib/features/duel/pre_match_ready_screen.dart',
    ).readAsStringSync();

    expect(duel, contains("context.tr('forfeit_and_leave')"));
    expect(duel, contains('needsSettlement'));
    expect(duel, contains("action.startsWith('rematch:')"));
    expect(prematch, contains('controller.forfeit();'));
    expect(prematch, contains('snapshot.coinSettlement != null'));
    expect(prematch, contains('await controller.dispose();'));
  });
}
