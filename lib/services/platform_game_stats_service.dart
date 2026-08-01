import 'dart:async';

import 'package:flutter/foundation.dart';

import 'online_duel_models.dart';
import 'platform_game_services.dart';
import 'social_api_client.dart';

enum PlatformGameStatsStatus {
  submitted,
  skipped,
  duplicate,
  notConfigured,
  notAuthenticated,
  failed,
}

class PlatformGameStatsResult {
  const PlatformGameStatsResult({required this.status, this.error});

  final PlatformGameStatsStatus status;
  final Object? error;

  bool get submitted => status == PlatformGameStatsStatus.submitted;
}

class PlatformGameStatsProfile {
  const PlatformGameStatsProfile({
    required this.currentElo,
    required this.winStreak,
  });

  final int currentElo;
  final int winStreak;
}

abstract interface class PlatformGameStatsMirror {
  void observeSnapshot(OnlineDuelSnapshot snapshot);

  Future<PlatformGameStatsResult> mirrorFinalStats(
    OnlineDuelSnapshot snapshot,
  );
}

typedef PlatformGameStatsConfiguredCheck = Future<bool> Function();
typedef PlatformGameStatsAuthenticationRefresh = Future<bool> Function();
typedef PlatformGameStatsRecorder = Future<bool> Function(
  List<Map<String, Object?>> events,
);
typedef PlatformGameStatsProfileLoader =
    Future<PlatformGameStatsProfile> Function();

class PlatformGameStatsService implements PlatformGameStatsMirror {
  PlatformGameStatsService({
    TargetPlatform? platform,
    PlatformGameStatsConfiguredCheck? isConfigured,
    PlatformGameStatsAuthenticationRefresh? refreshAuthentication,
    PlatformGameStatsRecorder? recordEvents,
    PlatformGameStatsProfileLoader? loadProfile,
  }) : _platform = platform,
       _isConfigured =
           isConfigured ?? PlatformGameServices.instance.isConfigured,
       _refreshAuthentication =
           refreshAuthentication ??
           PlatformGameServices.instance.refreshAuthentication,
       _recordEvents =
           recordEvents ?? PlatformGameServices.instance.recordGameStatsEvents,
       _loadProfile = loadProfile ?? _loadAuthoritativeProfile;

  static final PlatformGameStatsService instance = PlatformGameStatsService();

  final TargetPlatform? _platform;
  final PlatformGameStatsConfiguredCheck _isConfigured;
  final PlatformGameStatsAuthenticationRefresh _refreshAuthentication;
  final PlatformGameStatsRecorder _recordEvents;
  final PlatformGameStatsProfileLoader _loadProfile;
  final Set<String> _processedMatchIds = <String>{};
  final Map<String, DateTime> _observedStartTimes = <String, DateTime>{};

  TargetPlatform? get _resolvedPlatform {
    if (_platform != null) return _platform;
    if (kIsWeb) return null;
    return defaultTargetPlatform;
  }

  Future<void> initialize() async {
    if (_resolvedPlatform != TargetPlatform.android) return;
    if (!await _isConfigured()) return;
    if (!await _refreshAuthentication()) return;
    final profile = await _loadProfileWithRetry();
    await _recordEvents(<Map<String, Object?>>[
      _progressEvent(profile.currentElo),
    ]);
  }

  @override
  void observeSnapshot(OnlineDuelSnapshot snapshot) {
    if (snapshot.mode != 'ranked') return;
    if (snapshot.status == OnlineDuelStatus.active ||
        snapshot.status == OnlineDuelStatus.paused) {
      _observedStartTimes.putIfAbsent(snapshot.matchId, () => snapshot.serverTime);
    }
  }

  @override
  Future<PlatformGameStatsResult> mirrorFinalStats(
    OnlineDuelSnapshot snapshot,
  ) async {
    if (_resolvedPlatform != TargetPlatform.android) {
      return const PlatformGameStatsResult(
        status: PlatformGameStatsStatus.skipped,
      );
    }
    if (snapshot.mode != 'ranked' ||
        (snapshot.status != OnlineDuelStatus.completed &&
            snapshot.status != OnlineDuelStatus.forfeited)) {
      return const PlatformGameStatsResult(
        status: PlatformGameStatsStatus.skipped,
      );
    }

    final localRating = snapshot.rating?[snapshot.youSeat];
    if (localRating == null || snapshot.matchId.trim().isEmpty) {
      return const PlatformGameStatsResult(
        status: PlatformGameStatsStatus.skipped,
      );
    }
    if (!_processedMatchIds.add(snapshot.matchId)) {
      return const PlatformGameStatsResult(
        status: PlatformGameStatsStatus.duplicate,
      );
    }

    try {
      if (!await _isConfigured()) {
        _processedMatchIds.remove(snapshot.matchId);
        return const PlatformGameStatsResult(
          status: PlatformGameStatsStatus.notConfigured,
        );
      }
      if (!await _refreshAuthentication()) {
        _processedMatchIds.remove(snapshot.matchId);
        return const PlatformGameStatsResult(
          status: PlatformGameStatsStatus.notAuthenticated,
        );
      }

      final profile = await _loadProfileWithRetry(
        expectedElo: localRating.afterGlobal,
      );
      final startTime = _observedStartTimes[snapshot.matchId];
      final durationSeconds = startTime == null
          ? 0.0
          : snapshot.serverTime
                .difference(startTime)
                .inMilliseconds
                .clamp(0, 24 * 60 * 60 * 1000) /
              1000.0;

      final submitted = await _recordEvents(<Map<String, Object?>>[
        <String, Object?>{
          'eventName': 'rankedMatchCompleted',
          'properties': <String, Object?>{
            'matchId': _typed('string', snapshot.matchId),
            'isWinner': _typed(
              'bool',
              snapshot.winnerSeat == snapshot.youSeat,
            ),
            'durationSeconds': _typed('double', durationSeconds),
            'globalEloAfter': _typed('int64', localRating.afterGlobal),
            'winStreakAfter': _typed('int64', profile.winStreak),
            'difficulty': _typed('string', snapshot.difficulty),
            'eloDelta': _typed('int64', localRating.deltaGlobal),
          },
        },
        _progressEvent(localRating.afterGlobal),
      ]);
      if (!submitted) {
        _processedMatchIds.remove(snapshot.matchId);
        return const PlatformGameStatsResult(
          status: PlatformGameStatsStatus.failed,
        );
      }
      _observedStartTimes.remove(snapshot.matchId);
      return const PlatformGameStatsResult(
        status: PlatformGameStatsStatus.submitted,
      );
    } catch (error) {
      _processedMatchIds.remove(snapshot.matchId);
      return PlatformGameStatsResult(
        status: PlatformGameStatsStatus.failed,
        error: error,
      );
    }
  }

  Future<PlatformGameStatsProfile> _loadProfileWithRetry({
    int? expectedElo,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final profile = await _loadProfile();
        if (expectedElo == null || profile.currentElo == expectedElo) {
          return profile;
        }
        lastError = StateError(
          'Backend profile ELO ${profile.currentElo} did not yet match '
          'settled ELO $expectedElo.',
        );
      } catch (error) {
        lastError = error;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Unable to load the competitive profile.');
  }

  static Future<PlatformGameStatsProfile> _loadAuthoritativeProfile() async {
    final profile = await SocialApiClient.instance.loadCompetitiveProfile();
    return PlatformGameStatsProfile(
      currentElo: profile.currentElo,
      winStreak: profile.winStreak,
    );
  }

  static Map<String, Object?> _progressEvent(int currentElo) {
    return <String, Object?>{
      'eventName': 'progressUpdate',
      'properties': <String, Object?>{
        'currentProgress': _typed('int64', currentElo),
      },
    };
  }

  static Map<String, Object?> _typed(String type, Object value) {
    return <String, Object?>{'type': type, 'value': value};
  }
}
