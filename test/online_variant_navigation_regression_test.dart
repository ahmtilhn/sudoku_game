import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online matchmaking keeps expert visible and variant-safe', () {
    final source = File(
      'lib/features/duel/matchmaking_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final buttonWidth = (constraints.maxWidth - 12) / 3;'));
    expect(source, contains('for (final difficulty in SudokuDifficulty.values)'));
    expect(source, contains('Future<VariantMatchmakingResult> _joinSelectedQueue()'));
    expect(source, contains("roomId.startsWith('classic16:')"));
    expect(source, isNot(contains('SocialApiClient.instance.activeMatch()')));
  });

  test('challenge notification navigation is owned by the root gate', () {
    final source = File(
      'lib/features/home/push_room_navigation_gate.dart',
    ).readAsStringSync();

    expect(source, contains('_push.openedChallengeId.addListener'));
    expect(source, contains('UxChallengeInvitationScreen('));
    expect(source, contains('_push.openedChallengeId.value = null;'));
    expect(source, isNot(contains('ModalRoute.of(context)?.isCurrent')));
  });

  test('profile identity card uses one aligned avatar axis', () {
    final source = File(
      'lib/features/social/profile_hub_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Widget _identityCard({');
    final end = source.indexOf('Widget _tabContent(', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final identityCard = source.substring(start, end);
    expect(identityCard, contains("'profile-identity-card'"));
    expect(identityCard, contains('PlayerAvatar('));
    expect(identityCard, contains('ConstrainedBox('));
    expect(identityCard, isNot(contains('DuelAsset.profilePro')));
  });

  test('backend room factory infers classic16 from the room id', () {
    final facade = File(
      'backend/social_worker/src/online_duel.ts',
    ).readAsStringSync();
    final factory = File(
      'backend/social_worker/src/online_duel_factory.ts',
    ).readAsStringSync();
    final matchmaking = File(
      'backend/social_worker/src/variant_matchmaking.ts',
    ).readAsStringSync();

    expect(facade, contains("from './online_duel_factory'"));
    expect(factory, contains("roomId.startsWith('classic16:')"));
    expect(matchmaking, contains('roomIdForVariant(input.variant)'));
  });
}
