import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_models.dart';
import 'package:sudoku_game/services/platform_leaderboard_service.dart';

void main() {
  const ids = PlatformLeaderboardIds(
    android: <PlatformLeaderboardScope, String>{
      PlatformLeaderboardScope.global: 'android-global',
      PlatformLeaderboardScope.beginner: 'android-beginner',
      PlatformLeaderboardScope.easy: 'android-easy',
      PlatformLeaderboardScope.medium: 'android-medium',
      PlatformLeaderboardScope.hard: 'android-hard',
      PlatformLeaderboardScope.expert: 'android-expert',
    },
    ios: <PlatformLeaderboardScope, String>{
      PlatformLeaderboardScope.global: 'ios-global',
      PlatformLeaderboardScope.beginner: 'ios-beginner',
      PlatformLeaderboardScope.easy: 'ios-easy',
      PlatformLeaderboardScope.medium: 'ios-medium',
      PlatformLeaderboardScope.hard: 'ios-hard',
      PlatformLeaderboardScope.expert: 'ios-expert',
    },
  );

  const placeholderIds = PlatformLeaderboardIds(
    android: <PlatformLeaderboardScope, String>{
      PlatformLeaderboardScope.global: 'REPLACE_WITH_ANDROID_GLOBAL_ID',
      PlatformLeaderboardScope.beginner: 'REPLACE_WITH_ANDROID_BEGINNER_ID',
      PlatformLeaderboardScope.easy: 'REPLACE_WITH_ANDROID_EASY_ID',
      PlatformLeaderboardScope.medium: 'REPLACE_WITH_ANDROID_MEDIUM_ID',
      PlatformLeaderboardScope.hard: 'REPLACE_WITH_ANDROID_HARD_ID',
      PlatformLeaderboardScope.expert: 'REPLACE_WITH_ANDROID_EXPERT_ID',
    },
    ios: <PlatformLeaderboardScope, String>{
      PlatformLeaderboardScope.global: 'REPLACE_WITH_IOS_GLOBAL_ID',
      PlatformLeaderboardScope.beginner: 'REPLACE_WITH_IOS_BEGINNER_ID',
      PlatformLeaderboardScope.easy: 'REPLACE_WITH_IOS_EASY_ID',
      PlatformLeaderboardScope.medium: 'REPLACE_WITH_IOS_MEDIUM_ID',
      PlatformLeaderboardScope.hard: 'REPLACE_WITH_IOS_HARD_ID',
      PlatformLeaderboardScope.expert: 'REPLACE_WITH_IOS_EXPERT_ID',
    },
  );

  test('submits settled ranked global and difficulty ELO once', () async {
    final submissions = <({String id, int score})>[];
    final service = PlatformLeaderboardService(
      ids: ids,
      platform: TargetPlatform.android,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      submitScore: ({required score, leaderboardId}) async {
        submissions.add((id: leaderboardId!, score: score));
        return true;
      },
    );

    final snapshot = _snapshot();
    final first = await service.mirrorFinalRatings(snapshot);
    final duplicate = await service.mirrorFinalRatings(snapshot);

    expect(first.status, PlatformLeaderboardMirrorStatus.submitted);
    expect(first.submittedScopes, <PlatformLeaderboardScope>[
      PlatformLeaderboardScope.global,
      PlatformLeaderboardScope.easy,
    ]);
    expect(submissions, <({String id, int score})>[
      (id: 'android-global', score: 1210),
      (id: 'android-easy', score: 1175),
    ]);
    expect(duplicate.status, PlatformLeaderboardMirrorStatus.duplicate);
    expect(submissions, hasLength(2));
  });

  test(
    'resubmits authoritative backend ratings after a missed match mirror',
    () async {
      final submissions = <({String id, int score})>[];
      final service = PlatformLeaderboardService(
        ids: ids,
        platform: TargetPlatform.android,
        isConfigured: () async => true,
        refreshAuthentication: () async => true,
        loadRatings: () async => <String, dynamic>{
          'ratings': <Map<String, Object>>[
            <String, Object>{'scope': 'global', 'rating': 1310},
            <String, Object>{'scope': 'easy', 'rating': 1275},
          ],
        },
        submitScore: ({required score, leaderboardId}) async {
          submissions.add((id: leaderboardId!, score: score));
          return true;
        },
      );

      final result = await service.syncAuthoritativeRatings();

      expect(result.status, PlatformLeaderboardMirrorStatus.submitted);
      expect(submissions, <({String id, int score})>[
        (id: 'android-global', score: 1310),
        (id: 'android-easy', score: 1275),
      ]);
    },
  );

  test('uses the local player seat rating', () async {
    final submissions = <int>[];
    final service = PlatformLeaderboardService(
      ids: ids,
      platform: TargetPlatform.iOS,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      submitScore: ({required score, leaderboardId}) async {
        submissions.add(score);
        return true;
      },
    );

    await service.mirrorFinalRatings(_snapshot(youSeat: 'B'));

    expect(submissions, <int>[990, 1010]);
  });

  test('does not submit friendly or cancelled results', () async {
    var calls = 0;
    final service = PlatformLeaderboardService(
      ids: ids,
      platform: TargetPlatform.android,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      submitScore: ({required score, leaderboardId}) async {
        calls++;
        return true;
      },
    );

    final friendly = await service.mirrorFinalRatings(
      _snapshot(mode: 'friendly'),
    );
    final cancelled = await service.mirrorFinalRatings(
      _snapshot(matchId: 'cancelled', status: 'cancelled'),
    );

    expect(friendly.status, PlatformLeaderboardMirrorStatus.skipped);
    expect(cancelled.status, PlatformLeaderboardMirrorStatus.skipped);
    expect(calls, 0);
  });

  test('keeps platform calls disabled while IDs are placeholders', () async {
    var configuredChecks = 0;
    final service = PlatformLeaderboardService(
      ids: placeholderIds,
      platform: TargetPlatform.android,
      isConfigured: () async {
        configuredChecks++;
        return true;
      },
      refreshAuthentication: () async => true,
      submitScore: ({required score, leaderboardId}) async => true,
    );

    final result = await service.mirrorFinalRatings(_snapshot());

    expect(result.status, PlatformLeaderboardMirrorStatus.notConfigured);
    expect(configuredChecks, 0);
  });

  test('retries a match after a transient submission failure', () async {
    var attempt = 0;
    final service = PlatformLeaderboardService(
      ids: ids,
      platform: TargetPlatform.android,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      submitScore: ({required score, leaderboardId}) async {
        attempt++;
        return attempt > 1;
      },
    );

    final failed = await service.mirrorFinalRatings(_snapshot());
    final retried = await service.mirrorFinalRatings(_snapshot());

    expect(failed.status, PlatformLeaderboardMirrorStatus.failed);
    expect(retried.status, PlatformLeaderboardMirrorStatus.submitted);
  });

  test('rejects out-of-range ELO before platform submission', () async {
    var calls = 0;
    final service = PlatformLeaderboardService(
      ids: ids,
      platform: TargetPlatform.android,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      submitScore: ({required score, leaderboardId}) async {
        calls++;
        return true;
      },
    );

    final result = await service.mirrorFinalRatings(
      _snapshot(afterGlobalA: 3001),
    );

    expect(result.status, PlatformLeaderboardMirrorStatus.failed);
    expect(calls, 0);
  });

  test('skips invalid authoritative ratings during startup sync', () async {
    final submissions = <({String id, int score})>[];
    final service = PlatformLeaderboardService(
      ids: ids,
      platform: TargetPlatform.android,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      loadRatings: () async => <String, dynamic>{
        'ratings': <Map<String, Object>>[
          <String, Object>{'scope': 'global', 'rating': 99},
          <String, Object>{'scope': 'easy', 'rating': 1200},
          <String, Object>{'scope': 'hard', 'rating': 3001},
        ],
      },
      submitScore: ({required score, leaderboardId}) async {
        submissions.add((id: leaderboardId!, score: score));
        return true;
      },
    );

    final result = await service.syncAuthoritativeRatings();

    expect(result.status, PlatformLeaderboardMirrorStatus.submitted);
    expect(submissions, <({String id, int score})>[
      (id: 'android-easy', score: 1200),
    ]);
  });
}

OnlineDuelSnapshot _snapshot({
  String matchId = 'match-1',
  String mode = 'ranked',
  String status = 'completed',
  String youSeat = 'A',
  int afterGlobalA = 1210,
}) {
  final puzzle = List<int>.filled(81, 0)..[0] = 1;
  return OnlineDuelSnapshot.fromJson(<String, dynamic>{
    'roomId': 'room-1',
    'matchId': matchId,
    'mode': mode,
    'difficulty': 'easy',
    'status': status,
    'youSeat': youSeat,
    'players': <String, dynamic>{
      'A': <String, dynamic>{
        'publicId': 'a',
        'username': 'alice',
        'displayName': 'Alice',
        'avatarKey': 'default',
        'ready': true,
        'screenLoaded': true,
        'connected': true,
      },
      'B': <String, dynamic>{
        'publicId': 'b',
        'username': 'bob',
        'displayName': 'Bob',
        'avatarKey': 'default',
        'ready': true,
        'screenLoaded': true,
        'connected': true,
      },
    },
    'puzzle': puzzle,
    'board': List<int>.filled(81, 1),
    'scores': <String, int>{'A': 100, 'B': 80},
    'mistakes': <String, int>{'A': 0, 'B': 1},
    'correctMoves': <String, int>{'A': 10, 'B': 8},
    'timeouts': <String, int>{'A': 0, 'B': 0},
    'currentTurnSeat': 'A',
    'turnNumber': 19,
    'serverTime': 1000,
    'revision': 9,
    'winnerSeat': 'A',
    'finishReason': 'board_completed',
    'rating': <String, dynamic>{
      'A': <String, int>{
        'beforeGlobal': 1190,
        'afterGlobal': afterGlobalA,
        'deltaGlobal': afterGlobalA - 1190,
        'beforeDifficulty': 1155,
        'afterDifficulty': 1175,
        'deltaDifficulty': 20,
      },
      'B': <String, int>{
        'beforeGlobal': 1010,
        'afterGlobal': 990,
        'deltaGlobal': -20,
        'beforeDifficulty': 1030,
        'afterDifficulty': 1010,
        'deltaDifficulty': -20,
      },
    },
  });
}
