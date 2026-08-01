import 'package:flutter/foundation.dart';

import 'online_duel_models.dart';
import 'platform_game_services.dart';

enum PlatformLeaderboardScope {
  global,
  beginner,
  easy,
  medium,
  hard,
  expert,
}

enum PlatformLeaderboardMirrorStatus {
  submitted,
  skipped,
  duplicate,
  notConfigured,
  notAuthenticated,
  failed,
}

class PlatformLeaderboardMirrorResult {
  const PlatformLeaderboardMirrorResult({
    required this.status,
    this.submittedScopes = const <PlatformLeaderboardScope>[],
    this.error,
  });

  final PlatformLeaderboardMirrorStatus status;
  final List<PlatformLeaderboardScope> submittedScopes;
  final Object? error;

  bool get submitted => status == PlatformLeaderboardMirrorStatus.submitted;
}

abstract interface class PlatformLeaderboardMirror {
  Future<PlatformLeaderboardMirrorResult> mirrorFinalRatings(
    OnlineDuelSnapshot snapshot,
  );
}

class PlatformLeaderboardIds {
  const PlatformLeaderboardIds({
    this.android = const <PlatformLeaderboardScope, String>{
      PlatformLeaderboardScope.global:
          'REPLACE_WITH_PLAY_GAMES_GLOBAL_PEAK_ELO_ID',
      PlatformLeaderboardScope.beginner:
          'REPLACE_WITH_PLAY_GAMES_BEGINNER_PEAK_ELO_ID',
      PlatformLeaderboardScope.easy:
          'REPLACE_WITH_PLAY_GAMES_EASY_PEAK_ELO_ID',
      PlatformLeaderboardScope.medium:
          'REPLACE_WITH_PLAY_GAMES_MEDIUM_PEAK_ELO_ID',
      PlatformLeaderboardScope.hard:
          'REPLACE_WITH_PLAY_GAMES_HARD_PEAK_ELO_ID',
      PlatformLeaderboardScope.expert:
          'REPLACE_WITH_PLAY_GAMES_EXPERT_PEAK_ELO_ID',
    },
    this.ios = const <PlatformLeaderboardScope, String>{
      PlatformLeaderboardScope.global:
          'REPLACE_WITH_GAME_CENTER_GLOBAL_PEAK_ELO_ID',
      PlatformLeaderboardScope.beginner:
          'REPLACE_WITH_GAME_CENTER_BEGINNER_PEAK_ELO_ID',
      PlatformLeaderboardScope.easy:
          'REPLACE_WITH_GAME_CENTER_EASY_PEAK_ELO_ID',
      PlatformLeaderboardScope.medium:
          'REPLACE_WITH_GAME_CENTER_MEDIUM_PEAK_ELO_ID',
      PlatformLeaderboardScope.hard:
          'REPLACE_WITH_GAME_CENTER_HARD_PEAK_ELO_ID',
      PlatformLeaderboardScope.expert:
          'REPLACE_WITH_GAME_CENTER_EXPERT_PEAK_ELO_ID',
    },
  });

  final Map<PlatformLeaderboardScope, String> android;
  final Map<PlatformLeaderboardScope, String> ios;

  String? idFor(TargetPlatform platform, PlatformLeaderboardScope scope) {
    final value = switch (platform) {
      TargetPlatform.android => android[scope],
      TargetPlatform.iOS => ios[scope],
      _ => null,
    };
    if (value == null || value.trim().isEmpty || value.startsWith('REPLACE_')) {
      return null;
    }
    return value;
  }
}

typedef PlatformConfiguredCheck = Future<bool> Function();
typedef PlatformAuthenticationRefresh = Future<bool> Function();
typedef PlatformScoreSubmitter = Future<bool> Function({
  required int score,
  String? leaderboardId,
});
typedef PlatformLeaderboardPresenter = Future<bool> Function({
  String? leaderboardId,
});

class PlatformLeaderboardService implements PlatformLeaderboardMirror {
  PlatformLeaderboardService({
    PlatformLeaderboardIds ids = const PlatformLeaderboardIds(),
    TargetPlatform? platform,
    PlatformConfiguredCheck? isConfigured,
    PlatformAuthenticationRefresh? refreshAuthentication,
    PlatformScoreSubmitter? submitScore,
    PlatformLeaderboardPresenter? showLeaderboard,
  }) : _ids = ids,
       _platform = platform,
       _isConfigured =
           isConfigured ?? PlatformGameServices.instance.isConfigured,
       _refreshAuthentication =
           refreshAuthentication ??
           PlatformGameServices.instance.refreshAuthentication,
       _submitScore = submitScore ?? PlatformGameServices.instance.submitScore,
       _showLeaderboard =
           showLeaderboard ?? PlatformGameServices.instance.showLeaderboard;

  static final PlatformLeaderboardService instance =
      PlatformLeaderboardService();

  final PlatformLeaderboardIds _ids;
  final TargetPlatform? _platform;
  final PlatformConfiguredCheck _isConfigured;
  final PlatformAuthenticationRefresh _refreshAuthentication;
  final PlatformScoreSubmitter _submitScore;
  final PlatformLeaderboardPresenter _showLeaderboard;
  final Set<String> _processedMatchIds = <String>{};

  TargetPlatform? get _resolvedPlatform {
    if (_platform != null) return _platform;
    if (kIsWeb) return null;
    return defaultTargetPlatform;
  }

  @override
  Future<PlatformLeaderboardMirrorResult> mirrorFinalRatings(
    OnlineDuelSnapshot snapshot,
  ) async {
    final platform = _resolvedPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }
    if (snapshot.mode != 'ranked' ||
        (snapshot.status != OnlineDuelStatus.completed &&
            snapshot.status != OnlineDuelStatus.forfeited)) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }

    final localRating = snapshot.rating?[snapshot.youSeat];
    final difficultyScope = scopeForDifficulty(snapshot.difficulty);
    if (localRating == null || difficultyScope == null) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }

    final globalId = _ids.idFor(
      platform,
      PlatformLeaderboardScope.global,
    );
    final difficultyId = _ids.idFor(platform, difficultyScope);
    if (globalId == null || difficultyId == null) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.notConfigured,
      );
    }

    if (!_processedMatchIds.add(snapshot.matchId)) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.duplicate,
      );
    }

    try {
      if (!await _isConfigured()) {
        _processedMatchIds.remove(snapshot.matchId);
        return const PlatformLeaderboardMirrorResult(
          status: PlatformLeaderboardMirrorStatus.notConfigured,
        );
      }
      if (!await _refreshAuthentication()) {
        _processedMatchIds.remove(snapshot.matchId);
        return const PlatformLeaderboardMirrorResult(
          status: PlatformLeaderboardMirrorStatus.notAuthenticated,
        );
      }

      final globalSubmitted = await _submitScore(
        score: localRating.afterGlobal,
        leaderboardId: globalId,
      );
      final difficultySubmitted = await _submitScore(
        score: localRating.afterDifficulty,
        leaderboardId: difficultyId,
      );
      if (!globalSubmitted || !difficultySubmitted) {
        _processedMatchIds.remove(snapshot.matchId);
        return const PlatformLeaderboardMirrorResult(
          status: PlatformLeaderboardMirrorStatus.failed,
        );
      }
      return PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.submitted,
        submittedScopes: <PlatformLeaderboardScope>[
          PlatformLeaderboardScope.global,
          difficultyScope,
        ],
      );
    } catch (error) {
      _processedMatchIds.remove(snapshot.matchId);
      return PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.failed,
        error: error,
      );
    }
  }

  Future<bool> show(PlatformLeaderboardScope scope) async {
    final platform = _resolvedPlatform;
    if (platform == null) return false;
    final leaderboardId = _ids.idFor(platform, scope);
    if (leaderboardId == null) return false;
    if (!await _isConfigured()) return false;
    if (!await _refreshAuthentication()) return false;
    return _showLeaderboard(leaderboardId: leaderboardId);
  }

  static PlatformLeaderboardScope? scopeForDifficulty(String difficulty) {
    return switch (difficulty) {
      'beginner' => PlatformLeaderboardScope.beginner,
      'easy' => PlatformLeaderboardScope.easy,
      'medium' => PlatformLeaderboardScope.medium,
      'hard' => PlatformLeaderboardScope.hard,
      'expert' => PlatformLeaderboardScope.expert,
      _ => null,
    };
  }
}
