import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SocialPlayer {
  const SocialPlayer({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.rating,
    required this.gamesPlayed,
    required this.wins,
    required this.achievementCount,
    this.friendshipStatus,
    this.lastPlayedAt,
  });

  final String publicId;
  final String username;
  final String displayName;
  final int rating;
  final int gamesPlayed;
  final int wins;
  final int achievementCount;
  final String? friendshipStatus;
  final DateTime? lastPlayedAt;

  double get winRate => gamesPlayed == 0 ? 0 : wins / gamesPlayed;

  factory SocialPlayer.fromJson(Map<String, dynamic> json) {
    return SocialPlayer(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      rating: (json['rating'] as num?)?.toInt() ?? 1000,
      gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      achievementCount: (json['achievementCount'] as num?)?.toInt() ?? 0,
      friendshipStatus: json['friendshipStatus']?.toString(),
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt']?.toString() ?? ''),
    );
  }
}

class SocialAchievement {
  const SocialAchievement({
    required this.id,
    required this.category,
    required this.title,
    required this.tier,
    required this.unlocked,
  });

  final String id;
  final String category;
  final String title;
  final String tier;
  final bool unlocked;

  factory SocialAchievement.fromJson(Map<String, dynamic> json) {
    return SocialAchievement(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? 'ranked',
      title: json['title']?.toString() ?? '',
      tier: json['tier']?.toString() ?? 'bronze',
      unlocked: json['unlocked'] == true,
    );
  }
}

class CompetitiveProfile {
  const CompetitiveProfile({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.currentElo,
    required this.rankName,
    required this.seasonPeak,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.winRate,
    required this.winStreak,
    required this.tournamentEntries,
    required this.tournamentPodiums,
    required this.countryContributions,
    required this.achievementCount,
    required this.achievementShowcase,
    required this.privateProfile,
    this.country,
    this.rank,
  });

  final String publicId;
  final String username;
  final String displayName;
  final String avatarKey;
  final String? country;
  final int currentElo;
  final int? rank;
  final String rankName;
  final int seasonPeak;
  final int wins;
  final int losses;
  final int draws;
  final double winRate;
  final int winStreak;
  final int tournamentEntries;
  final int tournamentPodiums;
  final int countryContributions;
  final int achievementCount;
  final List<SocialAchievement> achievementShowcase;
  final bool privateProfile;

  factory CompetitiveProfile.fromJson(Map<String, dynamic> json) {
    final showcase = json['achievementShowcase'];
    return CompetitiveProfile(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      avatarKey: json['avatarKey']?.toString() ?? 'default',
      country: json['country']?.toString(),
      currentElo: (json['currentElo'] as num?)?.toInt() ?? 1000,
      rank: (json['rank'] as num?)?.toInt(),
      rankName: json['rankName']?.toString() ?? 'Bronze',
      seasonPeak: (json['seasonPeak'] as num?)?.toInt() ?? 1000,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble() ?? 0,
      winStreak: (json['winStreak'] as num?)?.toInt() ?? 0,
      tournamentEntries: (json['tournamentEntries'] as num?)?.toInt() ?? 0,
      tournamentPodiums: (json['tournamentPodiums'] as num?)?.toInt() ?? 0,
      countryContributions:
          (json['countryContributions'] as num?)?.toInt() ?? 0,
      achievementCount: (json['achievementCount'] as num?)?.toInt() ?? 0,
      achievementShowcase: showcase is List
          ? showcase
                .whereType<Map>()
                .map(
                  (value) =>
                      SocialAchievement.fromJson(value.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <SocialAchievement>[],
      privateProfile: json['privateProfile'] == true,
    );
  }
}

class SocialChallenge {
  const SocialChallenge({
    required this.id,
    this.variant = 'classic',
    required this.difficulty,
    required this.status,
    required this.challenger,
    required this.recipient,
    required this.expiresAt,
    this.roomId,
  });

  final String id;
  final String variant;
  final String difficulty;
  final String status;
  final SocialPlayer challenger;
  final SocialPlayer recipient;
  final DateTime expiresAt;
  final String? roomId;

  factory SocialChallenge.fromJson(Map<String, dynamic> json) {
    return SocialChallenge(
      id: json['id']?.toString() ?? '',
      variant: json['variant']?.toString() ?? 'classic',
      difficulty: json['difficulty']?.toString() ?? 'easy',
      status: json['status']?.toString() ?? 'pending',
      challenger: SocialPlayer.fromJson(
        (json['challenger'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      recipient: SocialPlayer.fromJson(
        (json['recipient'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
      roomId: json['roomId']?.toString(),
    );
  }
}

class MatchmakingResult {
  const MatchmakingResult({
    required this.status,
    this.variant = 'classic',
    required this.difficulty,
    this.roomId,
  });

  final String status;
  final String variant;
  final String difficulty;
  final String? roomId;

  factory MatchmakingResult.fromJson(Map<String, dynamic> json) {
    return MatchmakingResult(
      status: json['status']?.toString() ?? 'queued',
      variant: json['variant']?.toString() ?? 'classic',
      difficulty: json['difficulty']?.toString() ?? 'easy',
      roomId: json['roomId']?.toString(),
    );
  }
}

class SocialApiException implements Exception {
  const SocialApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => '$statusCode: $message';
}

class SocialApiClient {
  SocialApiClient._();

  static final SocialApiClient instance = SocialApiClient._();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'SOCIAL_BACKEND_URL',
  );
  static const String _debugFallbackBaseUrl =
      'https://sudoku-duel-social-staging.ilhanahmet246.workers.dev';
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _appCheckTimeout = Duration(seconds: 5);

  final http.Client _client = http.Client();

  static String get _baseUrl {
    final configured = _configuredBaseUrl.trim();
    final selected = configured.isNotEmpty
        ? configured
        : kDebugMode
        ? _debugFallbackBaseUrl
        : '';
    return _withoutTrailingSlashes(selected);
  }

  static String _withoutTrailingSlashes(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  bool get configured {
    final uri = Uri.tryParse(_baseUrl);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  String get baseUrl => _baseUrl;

  bool get usingDebugFallback =>
      kDebugMode && _configuredBaseUrl.trim().isEmpty;

  Uri websocketUri(String path) {
    if (!configured) {
      throw const SocialApiException(
        0,
        'The social backend URL is not configured.',
      );
    }
    final base = Uri.parse(_baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: path,
      query: '',
    );
  }

  Future<SocialPlayer> ensureProfile({String? displayName}) async {
    final response = await _request(
      'POST',
      '/v1/me',
      body: <String, Object?>{'displayName': displayName},
    );
    return SocialPlayer.fromJson(response);
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _request(
      'PUT',
      '/v1/me/devices/current',
      body: <String, Object>{'token': token, 'platform': platform},
    );
  }

  Future<void> disableCurrentDeviceToken() async {
    if (!configured) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _request(
      'DELETE',
      '/v1/me/devices/current',
      body: <String, Object>{'token': token},
    );
  }

  Future<List<SocialPlayer>> searchPlayers(String query) async {
    if (query.trim().length < 3) return const <SocialPlayer>[];
    final response = await _request(
      'GET',
      '/v1/players/search?q=${Uri.encodeQueryComponent(query.trim())}',
    );
    return _playerList(response['players']);
  }

  Future<List<SocialPlayer>> loadFriends() async {
    final response = await _request('GET', '/v1/friends');
    return _playerList(response['players']);
  }

  Future<List<SocialPlayer>> loadIncomingFriendRequests() async {
    final response = await _request('GET', '/v1/friends/requests');
    return _playerList(response['players']);
  }

  Future<List<SocialPlayer>> loadRecentOpponents() async {
    final response = await _request('GET', '/v1/opponents/recent');
    return _playerList(response['players']);
  }

  Future<void> sendFriendRequest(String targetPublicId) async {
    await _request(
      'POST',
      '/v1/friends/requests',
      body: <String, Object>{'targetPublicId': targetPublicId},
    );
  }

  Future<void> respondToFriendRequest({
    required String requesterPublicId,
    required bool accept,
  }) async {
    await _request(
      'POST',
      '/v1/friends/requests/respond',
      body: <String, Object>{
        'requesterPublicId': requesterPublicId,
        'action': accept ? 'accept' : 'decline',
      },
    );
  }

  Future<SocialChallenge> createChallenge({
    required String recipientPublicId,
    required String difficulty,
    String variant = 'classic',
  }) async {
    final response = await _request(
      'POST',
      '/v1/challenges',
      body: <String, Object>{
        'recipientPublicId': recipientPublicId,
        'variant': variant,
        'difficulty': difficulty,
      },
    );
    return SocialChallenge.fromJson(response);
  }

  Future<List<SocialChallenge>> loadPendingChallenges() async {
    final response = await _request('GET', '/v1/challenges?status=pending');
    final values = response['challenges'];
    if (values is! List) return const <SocialChallenge>[];
    return values
        .whereType<Map>()
        .map((value) => SocialChallenge.fromJson(value.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<SocialChallenge> loadChallenge(String challengeId) async {
    final response = await _request(
      'GET',
      '/v1/challenges/${Uri.encodeComponent(challengeId)}',
    );
    return SocialChallenge.fromJson(response);
  }

  Future<SocialChallenge> cancelChallenge(String challengeId) async {
    final response = await _request(
      'DELETE',
      '/v1/challenges/${Uri.encodeComponent(challengeId)}',
    );
    return SocialChallenge.fromJson(response);
  }

  Future<SocialChallenge> respondToChallenge({
    required String challengeId,
    required bool accept,
  }) async {
    final response = await _request(
      'POST',
      '/v1/challenges/$challengeId/respond',
      body: <String, Object>{'action': accept ? 'accept' : 'decline'},
    );
    return SocialChallenge.fromJson(response);
  }

  Future<MatchmakingResult> joinRankedQueue({
    required String difficulty,
    String variant = 'classic',
  }) async {
    final response = await _request(
      'POST',
      '/v1/matchmaking/queue',
      body: <String, Object>{
        'variant': variant,
        'difficulty': difficulty,
      },
    );
    return MatchmakingResult.fromJson(response);
  }

  Future<void> cancelRankedQueue() async {
    await _request('DELETE', '/v1/matchmaking/queue');
  }

  Future<Map<String, dynamic>?> activeMatch() async {
    final response = await _request('GET', '/v1/matches/active');
    final match = response['match'];
    return match is Map ? match.cast<String, dynamic>() : null;
  }

  Future<Map<String, dynamic>> loadLeaderboard(String scope) async {
    return _request('GET', '/v1/leaderboards/$scope');
  }

  Future<CompetitiveProfile> loadCompetitiveProfile() async {
    final response = await _request('GET', '/v1/competitive/profile');
    return CompetitiveProfile.fromJson(response);
  }

  Future<Map<String, dynamic>> loadCompetitiveLeaderboard(
    String scope, {
    String mode = 'top',
    String? cursor,
  }) async {
    final query = <String, String>{'mode': mode};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final suffix = Uri(queryParameters: query).query;
    return _request('GET', '/v1/competitive/leaderboards/$scope?$suffix');
  }

  Future<Map<String, dynamic>> loadRatings() async {
    return _request('GET', '/v1/me/ratings');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (!configured) {
      throw const SocialApiException(
        0,
        'The social backend URL is not configured.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SocialApiException(401, 'A Firebase session is required.');
    }

    final String? idToken;
    try {
      idToken = await user.getIdToken().timeout(_requestTimeout);
    } on TimeoutException {
      throw const SocialApiException(
        0,
        'Firebase session refresh timed out. Please try again.',
      );
    } on FirebaseAuthException catch (error) {
      throw SocialApiException(
        401,
        error.message ?? 'Unable to refresh the Firebase session.',
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const SocialApiException(
        401,
        'Unable to obtain a Firebase ID token.',
      );
    }

    final uri = Uri.parse('$_baseUrl$path');
    final appCheckToken = await _appCheckToken();
    final headers = <String, String>{
      'authorization': 'Bearer $idToken',
      'accept': 'application/json',
      ...?appCheckToken == null
          ? null
          : <String, String>{'x-firebase-appcheck': appCheckToken},
      if (body != null) 'content-type': 'application/json',
    };

    final Future<http.Response> responseFuture = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
      'PUT' => _client.put(
        uri,
        headers: headers,
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
      'DELETE' => _client.delete(
        uri,
        headers: headers,
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
      _ => throw ArgumentError.value(method, 'method'),
    };

    final http.Response response;
    try {
      response = await responseFuture.timeout(_requestTimeout);
    } on TimeoutException {
      throw const SocialApiException(
        0,
        'The social server did not respond in time. Please try again.',
      );
    } on http.ClientException catch (error) {
      throw SocialApiException(
        0,
        error.message.isEmpty
            ? 'Unable to connect to the social server.'
            : error.message,
      );
    }

    final Map<String, dynamic> decoded;
    if (response.body.isEmpty) {
      decoded = <String, dynamic>{};
    } else {
      try {
        final value = jsonDecode(response.body);
        if (value is! Map) throw const FormatException();
        decoded = Map<String, dynamic>.from(value);
      } catch (_) {
        throw SocialApiException(
          response.statusCode,
          'The social server returned an invalid response.',
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SocialApiException(
        response.statusCode,
        decoded['error']?.toString() ?? 'Social request failed.',
      );
    }
    return decoded;
  }

  List<SocialPlayer> _playerList(Object? value) {
    if (value is! List) return const <SocialPlayer>[];
    return value
        .whereType<Map>()
        .map((item) => SocialPlayer.fromJson(item.cast<String, dynamic>()))
        .where((player) => player.publicId.isNotEmpty)
        .toList(growable: false);
  }

  Future<String?> _appCheckToken() async {
    try {
      final token = await FirebaseAppCheck.instance
          .getToken(false)
          .timeout(_appCheckTimeout);
      return token == null || token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }
}
