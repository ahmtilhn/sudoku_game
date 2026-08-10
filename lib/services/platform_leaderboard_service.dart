import 'package:flutter/foundation.dart';

import 'online_duel_models.dart';
import 'platform_game_services.dart';
import 'social_api_client.dart';

enum PlatformLeaderboardScope { global, beginner, easy, medium, hard, expert }

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
      PlatformLeaderboardScope.global: 'CgkIzMyzm9saEAIQZQ',
      PlatformLeaderboardScope.beginner: 'CgkIzMyzm9saEAIQZg',
      PlatformLeaderboardScope.easy: 'CgkIzMyzm9saEAIQZw',
      PlatformLeaderboardScope.medium: 'CgkIzMyzm9saEAIQaA',
      PlatformLeaderboardScope.hard: 'CgkIzMyzm9saEAIQaQ',
      PlatformLeaderboardScope.expert: 'CgkIzMyzm9saEAIQag',
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
typedef PlatformAuthenticationRequest = Future<bool> Function();
typedef PlatformScoreSubmitter =
    Future<bool> Function({required int score, String? leaderboardId});
typedef PlatformLeaderboardPresenter =
    Future<bool> Function({String? leaderboardId});
typedef PlatformRatingsLoader = Future<Map<String, dynamic>> Function();

class PlatformLeaderboardService implements PlatformLeaderboardMirror {
  factory PlatformLeaderboardService({
    PlatformLeaderboardIds ids = const PlatformLeaderboardIds(),
    TargetPlatform? platform,
    PlatformConfiguredCheck? isConfigured,
    PlatformAuthenticationRefresh? refreshAuthentication,
    PlatformAuthenticationRequest? authenticate,
    PlatformScoreSubmitter? submitScore,
    PlatformLeaderboardPresenter? showLeaderboard,
    PlatformRatingsLoader? loadRatings,
  }) {
    return PlatformLeaderboardService._(
      ids,
      platform,
      isConfigured ?? PlatformGameServices.instance.isConfigured,
      refreshAuthentication ??
          PlatformGameServices.instance.refreshAuthentication,
      authenticate ??
          () => PlatformGameServices.instance.authenticate(
            notifyAccountBridge: false,
          ),
      submitScore ?? PlatformGameServices.instance.submitScore,
      showLeaderboard ?? PlatformGameServices.instance.showLeaderboard,
      loadRatings ?? SocialApiClient.instance.loadRatings,
    );
  }

  PlatformLeaderboardService._(
    this._ids,
    this._platform,
    this._isConfigured,
    this._refreshAuthentication,
    this._authenticate,
    this._submitScore,
    this._showLeaderboard,
    this._loadRatings,
  );

  static final PlatformLeaderboardService instance =
      PlatformLeaderboardService();

  final PlatformLeaderboardIds _ids;
  final TargetPlatform? _platform;
  final PlatformConfiguredCheck _isConfigured;
  final PlatformAuthenticationRefresh _refreshAuthentication;
  final PlatformAuthenticationRequest _authenticate;
  final PlatformScoreSubmitter _submitScore;
  final PlatformLeaderboardPresenter _showLeaderboard;
  final PlatformRatingsLoader _loadRatings;
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
    if (platform == null) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }
    if (snapshot.variant.key != 'classic9') {
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

    final globalId = _ids.idFor(platform, PlatformLeaderboardScope.global);
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
      if (!_isValidElo(localRating.afterGlobal) ||
          !_isValidElo(localRating.afterDifficulty)) {
        _processedMatchIds.remove(snapshot.matchId);
        return PlatformLeaderboardMirrorResult(
          status: PlatformLeaderboardMirrorStatus.failed,
          error: ArgumentError.value(
            '${localRating.afterGlobal}/${localRating.afterDifficulty}',
            'rating',
            'Platform leaderboard ELO must be between 100 and 3000.',
          ),
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

  Future<PlatformLeaderboardMirrorResult> syncAuthoritativeRatings() async {
    final platform = _resolvedPlatform;
    if (platform == null ||
        (platform != TargetPlatform.android &&
            platform != TargetPlatform.iOS)) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.skipped,
      );
    }
    if (!await _isConfigured()) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.notConfigured,
      );
    }
    var authenticated = await _refreshAuthentication();
    if (!authenticated) authenticated = await _authenticate();
    if (!authenticated) {
      return const PlatformLeaderboardMirrorResult(
        status: PlatformLeaderboardMirrorStatus.notAuthenticated,
      );
    }

    try {
      final response = await _loadRatings();
      final values = response['ratings'];
      if (values is! List) {
        return const PlatformLeaderboardMirrorResult(
          status: PlatformLeaderboardMirrorStatus.failed,
        );
      }
      final submitted = <PlatformLeaderboardScope>[];
      for (final value in values.whereType<Map>()) {
        final row = value.cast<String, dynamic>();
        final scopeName = row['scope']?.toString();
        final score = (row['rating'] as num?)?.toInt();
        final scope = scopeName == 'global'
            ? PlatformLeaderboardScope.global
            : scopeName == null
            ? null
            : scopeForDifficulty(scopeName);
        if (scope == null || score == null || !_isValidElo(score)) continue;
        final leaderboardId = _ids.idFor(platform, scope);
        if (leaderboardId == null) continue;
        if (await _submitScore(score: score, leaderboardId: leaderboardId)) {
          submitted.add(scope);
        }
      }
      return PlatformLeaderboardMirrorResult(
        status: submitted.isEmpty
            ? PlatformLeaderboardMirrorStatus.notConfigured
            : PlatformLeaderboardMirrorStatus.submitted,
        submittedScopes: submitted,
      );
    } catch (error) {
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
    var authenticated = await _refreshAuthentication();
    if (!authenticated) {
      authenticated = await _authenticate();
    }
    if (!authenticated) return false;
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

bool _isValidElo(int value) => value >= 100 && value <= 3000;
