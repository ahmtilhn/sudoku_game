import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/rank_identity_models.dart';
import 'firebase_services.dart';
import 'firebase_session_service.dart';
import 'social_api_client.dart';

class RankIdentityException implements Exception {
  const RankIdentityException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => message;
}

class RankCountryPreference {
  const RankCountryPreference({
    required this.countryCode,
    required this.flagVisible,
  });

  final String? countryCode;
  final bool flagVisible;

  factory RankCountryPreference.fromJson(Map<String, dynamic> json) {
    final raw = json['countryCode']?.toString().trim().toUpperCase();
    return RankCountryPreference(
      countryCode: raw == null || raw.isEmpty ? null : raw,
      flagVisible: json['countryFlagVisible'] != false,
    );
  }
}

class PublicRankSummary {
  const PublicRankSummary({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.rankPoints,
    required this.rankKey,
    required this.rankName,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.winRate,
  });

  final String publicId;
  final String username;
  final String displayName;
  final String avatarKey;
  final int rankPoints;
  final String rankKey;
  final String rankName;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final double winRate;

  factory PublicRankSummary.fromJson(Map<String, dynamic> json) {
    return PublicRankSummary(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      avatarKey: json['avatarKey']?.toString() ?? 'default',
      rankPoints: (json['rankPoints'] as num?)?.toInt() ?? 0,
      rankKey: json['rankKey']?.toString() ?? 'bronze_3',
      rankName: json['rankName']?.toString() ?? 'Bronze III',
      gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RankLeaderboardSnapshot {
  const RankLeaderboardSnapshot({
    required this.entries,
    this.currentRank,
    this.currentRankPoints,
    this.currentRankKey,
    this.currentRankName,
  });

  final List<RankLeaderboardEntry> entries;
  final int? currentRank;
  final int? currentRankPoints;
  final String? currentRankKey;
  final String? currentRankName;

  factory RankLeaderboardSnapshot.fromJson(Map<String, dynamic> json) {
    final values = json['entries'];
    final current = json['currentPlayer'];
    final currentMap = current is Map
        ? current.cast<String, dynamic>()
        : const <String, dynamic>{};
    return RankLeaderboardSnapshot(
      entries: values is List
          ? values
                .whereType<Map>()
                .map(
                  (item) => RankLeaderboardEntry.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <RankLeaderboardEntry>[],
      currentRank: (currentMap['rank'] as num?)?.toInt(),
      currentRankPoints: (currentMap['rankPoints'] as num?)?.toInt(),
      currentRankKey: currentMap['rankKey']?.toString(),
      currentRankName: currentMap['rankName']?.toString(),
    );
  }
}

class RankMatchReward {
  const RankMatchReward({
    required this.rankKey,
    required this.rankName,
    required this.amount,
  });

  final String rankKey;
  final String rankName;
  final int amount;

  factory RankMatchReward.fromJson(Map<String, dynamic> json) {
    return RankMatchReward(
      rankKey: json['rankKey']?.toString() ?? '',
      rankName: json['rankName']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }
}

class RankMatchResult {
  const RankMatchResult({
    required this.matchId,
    required this.rated,
    required this.settled,
    required this.rpBefore,
    required this.rpAfter,
    required this.rpDelta,
    required this.rankBeforeName,
    required this.rankAfterName,
    required this.rankUp,
    required this.rewardCoins,
    required this.rewards,
    required this.abandonmentPenalty,
    required this.repeatPercent,
  });

  final String matchId;
  final bool rated;
  final bool settled;
  final int rpBefore;
  final int rpAfter;
  final int rpDelta;
  final String rankBeforeName;
  final String rankAfterName;
  final bool rankUp;
  final int rewardCoins;
  final List<RankMatchReward> rewards;
  final int abandonmentPenalty;
  final int repeatPercent;

  factory RankMatchResult.fromJson(Map<String, dynamic> json) {
    final rewardsJson = json['rewards'];
    return RankMatchResult(
      matchId: json['matchId']?.toString() ?? '',
      rated: json['rated'] == true,
      settled: json['settled'] == true,
      rpBefore: (json['rpBefore'] as num?)?.toInt() ?? 0,
      rpAfter: (json['rpAfter'] as num?)?.toInt() ?? 0,
      rpDelta: (json['rpDelta'] as num?)?.toInt() ?? 0,
      rankBeforeName: json['rankBeforeName']?.toString() ?? 'Bronze III',
      rankAfterName: json['rankAfterName']?.toString() ?? 'Bronze III',
      rankUp: json['rankUp'] == true,
      rewardCoins: (json['rewardCoins'] as num?)?.toInt() ?? 0,
      rewards: rewardsJson is List
          ? rewardsJson
                .whereType<Map>()
                .map(
                  (value) => RankMatchReward.fromJson(
                    value.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <RankMatchReward>[],
      abandonmentPenalty:
          (json['abandonmentPenalty'] as num?)?.toInt() ?? 0,
      repeatPercent: (json['repeatPercent'] as num?)?.toInt() ?? 100,
    );
  }
}

class RankIdentityService {
  RankIdentityService._();

  static final RankIdentityService instance = RankIdentityService._();
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client = http.Client();
  final ValueNotifier<RankIdentityProfile?> current =
      ValueNotifier<RankIdentityProfile?>(null);

  Future<RankIdentityProfile> load({bool force = false}) async {
    if (!force && current.value != null) return current.value!;
    final value = RankIdentityProfile.fromJson(
      await _request('GET', '/v1/me/rank-profile'),
    );
    current.value = value;
    return value;
  }

  Future<RankIdentityProfile> refresh() => load(force: true);

  Future<PublicRankSummary> loadPublicRankSummary(String publicId) async {
    return PublicRankSummary.fromJson(
      await _request(
        'GET',
        '/v1/competitive/rank-player/${Uri.encodeComponent(publicId.trim())}',
      ),
    );
  }

  Future<RankIdentityProfile> save({
    String? avatarKey,
    String? frameKey,
    String? titleKey,
    List<String>? achievementIds,
  }) async {
    final body = <String, Object?>{
      'avatarKey': ?avatarKey,
      'frameKey': ?frameKey,
      'titleKey': ?titleKey,
      'achievementIds': ?achievementIds,
    };
    final value = RankIdentityProfile.fromJson(
      await _request('PUT', '/v1/me/rank-profile', body: body),
    );
    current.value = value;
    return value;
  }

  Future<RankCountryPreference> loadCountryPreference() async {
    return RankCountryPreference.fromJson(
      await _request('GET', '/v1/me/rank-country'),
    );
  }

  Future<RankCountryPreference> saveCountryPreference({
    String? countryCode,
    required bool flagVisible,
  }) async {
    return RankCountryPreference.fromJson(
      await _request(
        'PUT',
        '/v1/me/rank-country',
        body: <String, Object?>{
          'countryCode': countryCode ?? '',
          'countryFlagVisible': flagVisible,
        },
      ),
    );
  }

  Future<Map<String, String>> loadRankCountryFlags({int limit = 50}) async {
    final safe = limit.clamp(1, 100);
    final payload = await _request(
      'GET',
      '/v1/competitive/rank-country-flags?limit=$safe',
    );
    final values = payload['entries'];
    if (values is! List) return const <String, String>{};
    final result = <String, String>{};
    for (final item in values.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final publicId = map['publicId']?.toString().trim() ?? '';
      final code = map['countryCode']?.toString().trim().toUpperCase() ?? '';
      if (publicId.isNotEmpty && RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
        result[publicId] = code;
      }
    }
    return result;
  }

  Future<RankLeaderboardSnapshot> loadLeaderboard({int limit = 50}) async {
    final safe = limit.clamp(1, 100);
    return RankLeaderboardSnapshot.fromJson(
      await _request(
        'GET',
        '/v1/competitive/rank-leaderboard?limit=$safe',
      ),
    );
  }

  /// Reads the derived visible-RP settlement after the authoritative online
  /// match has finished. Rank settlement is deliberately additive, so tolerate
  /// the short propagation/reconciliation window instead of presenting a
  /// finished ranked match as a permanent zero-RP result.
  Future<RankMatchResult> loadMatchResult(String matchId) async {
    RankMatchResult? latest;
    RankIdentityException? lastTransientError;
    const maxAttempts = 16;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        latest = RankMatchResult.fromJson(
          await _request(
            'GET',
            '/v1/me/rank-match-result/${Uri.encodeComponent(matchId)}',
          ),
        );
        lastTransientError = null;
        if (!latest.rated || latest.settled) return latest;
      } on RankIdentityException catch (error) {
        final transient =
            error.statusCode == 0 ||
            error.statusCode == 429 ||
            error.statusCode >= 500;
        if (!transient || attempt == maxAttempts - 1) rethrow;
        lastTransientError = error;
      }

      if (attempt < maxAttempts - 1) {
        final delayMs = 220 + (attempt.clamp(0, 6) * 45);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    if (latest != null) return latest;
    if (lastTransientError != null) throw lastTransientError;
    return RankMatchResult(
      matchId: matchId,
      rated: true,
      settled: false,
      rpBefore: 0,
      rpAfter: 0,
      rpDelta: 0,
      rankBeforeName: 'Bronze III',
      rankAfterName: 'Bronze III',
      rankUp: false,
      rewardCoins: 0,
      rewards: const <RankMatchReward>[],
      abandonmentPenalty: 0,
      repeatPercent: 100,
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final social = SocialApiClient.instance;
    if (!social.configured) {
      throw const RankIdentityException(
        0,
        'The online profile server is not configured.',
        code: 'backend_not_configured',
      );
    }

    final user = await FirebaseSessionService.ensureAnonymousSession();
    final String? idToken;
    try {
      idToken = await user.getIdToken().timeout(_timeout);
    } on TimeoutException {
      throw const RankIdentityException(
        0,
        'Player session refresh timed out.',
        code: 'auth_timeout',
      );
    } on FirebaseAuthException catch (error) {
      throw RankIdentityException(
        401,
        error.message ?? 'Unable to refresh the player session.',
        code: error.code,
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const RankIdentityException(
        401,
        'Unable to obtain a player token.',
        code: 'missing_token',
      );
    }

    final appCheckToken = await FirebaseServices.instance.tryGetAppCheckToken(
      timeout: _timeout,
    );
    final uri = Uri.parse('${social.baseUrl}$path');
    final headers = <String, String>{
      'authorization': 'Bearer $idToken',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (appCheckToken != null && appCheckToken.isNotEmpty)
        'x-firebase-appcheck': appCheckToken,
    };

    final Future<http.Response> pending = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'PUT' => _client.put(
        uri,
        headers: headers,
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
      _ => throw ArgumentError.value(method, 'method'),
    };

    final http.Response response;
    try {
      response = await pending.timeout(_timeout);
    } on TimeoutException {
      throw const RankIdentityException(
        0,
        'The rank server did not respond in time.',
        code: 'request_timeout',
      );
    } on http.ClientException catch (error) {
      throw RankIdentityException(
        0,
        error.message.isEmpty
            ? 'Unable to connect to the rank server.'
            : error.message,
        code: 'network_error',
      );
    }

    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        final value = jsonDecode(response.body);
        if (value is! Map) throw const FormatException();
        decoded = value.cast<String, dynamic>();
      } catch (_) {
        throw RankIdentityException(
          response.statusCode,
          'The rank server returned an invalid response.',
          code: 'invalid_response',
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RankIdentityException(
        response.statusCode,
        decoded['error']?.toString() ?? 'Rank profile request failed.',
        code: decoded['code']?.toString(),
      );
    }
    return decoded;
  }
}
