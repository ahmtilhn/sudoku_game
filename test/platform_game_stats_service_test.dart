import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/online_duel_models.dart';
import 'package:sudoku_game/services/platform_game_stats_service.dart';

void main() {
  test(
    'submits ranked match and progress events with authoritative values',
    () async {
      final recorded = <Map<String, Object?>>[];
      final service = PlatformGameStatsService(
        platform: TargetPlatform.android,
        isConfigured: () async => true,
        refreshAuthentication: () async => true,
        loadProfile: () async =>
            const PlatformGameStatsProfile(currentElo: 1216, winStreak: 4),
        recordEvents: (events) async {
          recorded.addAll(events);
          return true;
        },
      );

      service.observeSnapshot(
        _snapshot(
          status: OnlineDuelStatus.active,
          serverTime: DateTime.utc(2026, 8, 1, 20),
        ),
      );
      final result = await service.mirrorFinalStats(
        _snapshot(
          status: OnlineDuelStatus.completed,
          serverTime: DateTime.utc(2026, 8, 1, 20, 2),
        ),
      );

      expect(result.status, PlatformGameStatsStatus.submitted);
      expect(recorded, hasLength(2));
      expect(recorded.first['eventName'], 'rankedMatchCompleted');
      final properties = (recorded.first['properties'] as Map)
          .cast<String, Object?>();
      expect(_value(properties, 'matchId'), 'match-1');
      expect(_value(properties, 'isWinner'), isTrue);
      expect(_value(properties, 'durationSeconds'), 120.0);
      expect(_value(properties, 'globalEloAfter'), 1216);
      expect(_value(properties, 'winStreakAfter'), 4);
      expect(_value(properties, 'difficulty'), 'hard');
      expect(_value(properties, 'eloDelta'), 16);
      expect(recorded.last['eventName'], 'progressUpdate');
    },
  );

  test('does not submit friendly matches', () async {
    var calls = 0;
    final service = PlatformGameStatsService(
      platform: TargetPlatform.android,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      loadProfile: () async =>
          const PlatformGameStatsProfile(currentElo: 1216, winStreak: 1),
      recordEvents: (_) async {
        calls++;
        return true;
      },
    );

    final result = await service.mirrorFinalStats(
      _snapshot(mode: 'friendly', status: OnlineDuelStatus.completed),
    );

    expect(result.status, PlatformGameStatsStatus.skipped);
    expect(calls, 0);
  });

  test('deduplicates a successfully submitted match', () async {
    var calls = 0;
    final service = PlatformGameStatsService(
      platform: TargetPlatform.android,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      loadProfile: () async =>
          const PlatformGameStatsProfile(currentElo: 1216, winStreak: 2),
      recordEvents: (_) async {
        calls++;
        return true;
      },
    );
    final snapshot = _snapshot(status: OnlineDuelStatus.completed);

    expect(
      (await service.mirrorFinalStats(snapshot)).status,
      PlatformGameStatsStatus.submitted,
    );
    expect(
      (await service.mirrorFinalStats(snapshot)).status,
      PlatformGameStatsStatus.duplicate,
    );
    expect(calls, 1);
  });

  test('startup sync sends current Global ELO as progressUpdate', () async {
    final recorded = <Map<String, Object?>>[];
    final service = PlatformGameStatsService(
      platform: TargetPlatform.android,
      isConfigured: () async => true,
      refreshAuthentication: () async => true,
      loadProfile: () async =>
          const PlatformGameStatsProfile(currentElo: 1450, winStreak: 0),
      recordEvents: (events) async {
        recorded.addAll(events);
        return true;
      },
    );

    await service.initialize();

    expect(recorded, hasLength(1));
    expect(recorded.single['eventName'], 'progressUpdate');
    final properties = (recorded.single['properties'] as Map)
        .cast<String, Object?>();
    expect(_value(properties, 'currentProgress'), 1450);
  });
}

Object? _value(Map<String, Object?> properties, String key) {
  return (properties[key] as Map)['value'];
}

OnlineDuelSnapshot _snapshot({
  String mode = 'ranked',
  required OnlineDuelStatus status,
  DateTime? serverTime,
}) {
  const player = OnlineDuelPlayer(
    publicId: 'player',
    username: 'player',
    displayName: 'Player',
    avatarKey: 'default',
    ready: true,
    screenLoaded: true,
    connected: true,
  );
  return OnlineDuelSnapshot(
    roomId: 'room-1',
    matchId: 'match-1',
    mode: mode,
    difficulty: 'hard',
    status: status,
    youSeat: OnlineDuelSeat.a,
    players: const <OnlineDuelSeat, OnlineDuelPlayer>{
      OnlineDuelSeat.a: player,
      OnlineDuelSeat.b: player,
    },
    puzzle: List<int>.filled(81, 0),
    board: List<int>.filled(81, 0),
    scores: const <OnlineDuelSeat, int>{
      OnlineDuelSeat.a: 100,
      OnlineDuelSeat.b: 90,
    },
    mistakes: const <OnlineDuelSeat, int>{
      OnlineDuelSeat.a: 0,
      OnlineDuelSeat.b: 1,
    },
    correctMoves: const <OnlineDuelSeat, int>{
      OnlineDuelSeat.a: 10,
      OnlineDuelSeat.b: 9,
    },
    timeouts: const <OnlineDuelSeat, int>{
      OnlineDuelSeat.a: 0,
      OnlineDuelSeat.b: 0,
    },
    currentTurnSeat: OnlineDuelSeat.a,
    turnNumber: 20,
    serverTime: serverTime ?? DateTime.utc(2026, 8, 1, 20, 2),
    revision: 42,
    winnerSeat: OnlineDuelSeat.a,
    rating: const <OnlineDuelSeat, OnlineDuelRatingChange>{
      OnlineDuelSeat.a: OnlineDuelRatingChange(
        beforeGlobal: 1200,
        afterGlobal: 1216,
        deltaGlobal: 16,
        beforeDifficulty: 1180,
        afterDifficulty: 1196,
        deltaDifficulty: 16,
      ),
      OnlineDuelSeat.b: OnlineDuelRatingChange(
        beforeGlobal: 1200,
        afterGlobal: 1184,
        deltaGlobal: -16,
        beforeDifficulty: 1180,
        afterDifficulty: 1164,
        deltaDifficulty: -16,
      ),
    },
  );
}
