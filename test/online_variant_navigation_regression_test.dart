import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online matchmaking keeps expert visible and variant-safe', () {
    final source = File(
      'lib/features/duel/matchmaking_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('final buttonWidth = (constraints.maxWidth - 12) / 3;'),
    );
    expect(
      source,
      contains('for (final difficulty in SudokuDifficulty.values)'),
    );
    expect(
      source,
      contains('Future<VariantMatchmakingResult> _joinSelectedQueue()'),
    );
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
    expect(identityCard, contains('localAvatarBytes: avatarBytes'));
    expect(identityCard, contains('Expanded('));
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

  test('backend settlement updates variant-scoped ELO rows', () {
    final source = File(
      'backend/social_worker/src/index.ts',
    ).readAsStringSync();

    expect(source, contains("variant: match.variant === 'classic16'"));
    expect(source, contains('stateVariant(duel)'));
    expect(source, contains('FROM player_variant_ratings'));
    expect(source, contains('UPDATE player_variant_ratings'));
    expect(source, contains("if (variant !== 'classic9') return statements;"));
  });

  test('backend ELO endpoints read variant-scoped leaderboard rows', () {
    final mainRouter = File(
      'backend/social_worker/src/index.ts',
    ).readAsStringSync();
    final competitive = File(
      'backend/social_worker/src/competitive.ts',
    ).readAsStringSync();
    final profileWrapper = File(
      'backend/social_worker/src/profile_wrapper.ts',
    ).readAsStringSync();

    expect(mainRouter, contains('normalizeRatingVariant'));
    expect(mainRouter, contains('FROM player_variant_ratings'));
    expect(mainRouter, contains("SELECT player_id, 'classic9', scope, rating"));
    expect(mainRouter, contains('WHERE player_id = ? AND variant = ?'));
    expect(mainRouter, contains('WHERE pr.variant = ? AND pr.scope = ?'));
    expect(competitive, contains('variant?: \'classic9\' | \'classic16\''));
    expect(competitive, contains('FROM player_variant_ratings pr'));
    expect(competitive, contains("SELECT player_id, 'classic9', scope, rating"));
    expect(
      competitive,
      contains('ON other.variant = mine.variant AND other.scope = mine.scope'),
    );
    expect(profileWrapper, contains('normalizeRatingVariant'));
    expect(
      profileWrapper,
      contains("value === 'classic16' ? 'classic16' : 'classic9'"),
    );
  });
}
