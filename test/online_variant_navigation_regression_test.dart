import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'online matchmaking keeps expert visible, variant-safe, and cancel-race safe',
    () {
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
      expect(source, contains('final pending = _activeQueueRequest;'));
      expect(source, contains('await _matchmaking.cancelRankedQueue();'));
      expect(source, contains('SocialApiClient.instance.activeMatch()'));

      final sessionIndex = source.indexOf(
        'await FirebaseSessionService.ensureAnonymousSession();',
      );
      final findOpponentStart = source.indexOf('Future<void> _findOpponent()');
      final walletIndex = source.indexOf(
        'await _economy.refresh();',
        findOpponentStart,
      );
      final queueIndex = source.indexOf(
        'final result = await _joinSelectedQueue();',
        findOpponentStart,
      );
      expect(findOpponentStart, greaterThanOrEqualTo(0));
      expect(sessionIndex, greaterThanOrEqualTo(0));
      expect(walletIndex, greaterThan(sessionIndex));
      expect(queueIndex, greaterThan(walletIndex));
    },
  );

  test('profile loading does not open interactive platform sign-in', () {
    final source = File(
      'lib/services/player_profile_service.dart',
    ).readAsStringSync();

    expect(source, contains('var authenticated = await games.refreshAuthentication();'));
    expect(source, isNot(contains('authenticated = await games.authenticate();')));
    expect(
      source,
      contains('games.localPlayer.value ?? await games.getLocalPlayer()'),
    );
  });

  test('online duel builds the board from snapshot variant metadata', () {
    final source = File(
      'lib/features/duel/online_duel_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('solution: List<int>.filled(snapshot.cellCount, 1)'),
    );
    expect(source, contains('size: snapshot.boardSize'));
  });

  test('challenge navigation is deferred off the main route', () {
    final globalGate = File(
      'lib/features/home/push_room_navigation_gate.dart',
    ).readAsStringSync();
    final challengeGate = File(
      'lib/features/social/challenge_navigation_gate.dart',
    ).readAsStringSync();

    expect(globalGate, isNot(contains('_push.openedChallengeId.addListener')));
    expect(globalGate, isNot(contains('UxChallengeInvitationScreen(')));
    expect(globalGate, contains('ModalRoute.of(context)?.isCurrent'));

    expect(challengeGate, contains('_push.openedChallengeId.addListener'));
    expect(challengeGate, contains('ChallengeInvitationScreen('));
    expect(challengeGate, contains('ModalRoute.of(context)?.isCurrent'));
    expect(challengeGate, contains('_challengeOpenScheduled'));
  });

  test('profile identity card uses one aligned avatar axis', () {
    final source = File(
      'lib/features/social/competitive_profile_card.dart',
    ).readAsStringSync();
    final start = source.indexOf('class CompetitiveProfileCard');
    final end = source.indexOf('class _IdentityLine', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final identityCard = source.substring(start, end);
    expect(identityCard, contains('PlayerAvatar('));
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
    expect(matchmaking, contains('easierDifficulty(input.difficulty'));
    expect(matchmaking, isNot(contains('AND q.difficulty = ?')));
  });

  test('backend settlement updates variant-scoped ELO rows', () {
    final source = File(
      'backend/social_worker/src/index.ts',
    ).readAsStringSync();

    expect(source, contains('variant: duelVariant(match.variant)'));
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
    expect(
      competitive,
      contains("SELECT player_id, 'classic9', scope, rating"),
    );
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
