import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'firebase_services.dart';
import 'firebase_session_service.dart';

class SocialApiException implements Exception {
  const SocialApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => '$statusCode: $message';
}

class SocialPlayer {
  const SocialPlayer({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.rating,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.achievementCount,
    this.friendshipStatus,
  });

  final String publicId;
  final String username;
  final String displayName;
  final String avatarKey;
  final int rating;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int achievementCount;
  final String? friendshipStatus;

  factory SocialPlayer.fromJson(Map<String, dynamic> json) {
    return SocialPlayer(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Sudoku Player',
      avatarKey: json['avatarKey']?.toString() ?? 'grid_green',
      rating: _intFromJson(json['rating'], defaultValue: 1000),
      gamesPlayed: _intFromJson(json['gamesPlayed']),
      wins: _intFromJson(json['wins']),
      losses: _intFromJson(json['losses']),
      achievementCount: _intFromJson(json['achievementCount']),
      friendshipStatus: json['friendshipStatus']?.toString(),
    );
  }
}

class SocialChallenge {
  const SocialChallenge({
    required this.id,
    required this.status,
    required this.variant,
    required this.difficulty,
    required this.challenger,
    required this.recipient,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.roomId,
  });

  final String id;
  final String status;
  final String variant;
  final String difficulty;
  final SocialPlayer challenger;
  final SocialPlayer recipient;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final String? roomId;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  factory SocialChallenge.fromJson(Map<String, dynamic> json) {
    return SocialChallenge(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      variant: json['variant']?.toString() ?? 'classic',
      difficulty: json['difficulty']?.toString() ?? 'medium',
      challenger: SocialPlayer.fromJson(
        (json['challenger'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      recipient: SocialPlayer.fromJson(
        (json['recipient'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      createdAt: _dateFromJson(json['createdAt']),
      updatedAt: _dateFromJson(json['updatedAt']),
      expiresAt: _dateFromJson(json['expiresAt']),
      roomId: json['roomId']?.toString(),
    );
  }
}

class MatchmakingResult {
  const MatchmakingResult({
    required this.status,
    required this.difficulty,
    required this.playerId,
    this.roomId,
    this.rating,
    this.onlineCoins,
  });

  final String status;
  final String difficulty;
  final String playerId;
  final String? roomId;
  final int? rating;
  final int? onlineCoins;

  bool get matched => status == 'matched' && roomId != null;

  factory MatchmakingResult.fromJson(Map<String, dynamic> json) {
    return MatchmakingResult(
      status: json['status']?.toString() ?? 'queued',
      difficulty: json['difficulty']?.toString() ?? 'medium',
      playerId: json['playerId']?.toString() ?? '',
      roomId: json['roomId']?.toString(),
      rating: json['rating'] == null ? null : _intFromJson(json['rating']),
      onlineCoins: json['onlineCoins'] == null
          ? null
          : _intFromJson(json['onlineCoins']),
    );
  }
}

class CompetitiveProfile {
  const CompetitiveProfile({
    required this.rating,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.achievementCount,
    required this.rank,
    required this.rankProgress,
    required this.nextRankRating,
    required this.featuredAchievementIds,
  });

  final int rating;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int achievementCount;
  final String rank;
  final double rankProgress;
  final int nextRankRating;
  final List<String> featuredAchievementIds;

  factory CompetitiveProfile.fromJson(Map<String, dynamic> json) {
    final rawFeatured = json['featuredAchievementIds'];
    return CompetitiveProfile(
      rating: _intFromJson(json['rating'], defaultValue: 1000),
      gamesPlayed: _intFromJson(json['gamesPlayed']),
      wins: _intFromJson(json['wins']),
      losses: _intFromJson(json['losses']),
      achievementCount: _intFromJson(json['achievementCount']),
      rank: json['rank']?.toString() ?? 'bronze',
      rankProgress: _doubleFromJson(json['rankProgress']),
      nextRankRating: _intFromJson(json['nextRankRating']),
      featuredAchievementIds: rawFeatured is List
          ? rawFeatured.map((value) => value.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}

int _intFromJson(Object? value, {int defaultValue = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? defaultValue;
}

double _doubleFromJson(Object? value, {double defaultValue = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? defaultValue;
}

DateTime _dateFromJson(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

class SocialApiClient {
  SocialApiClient._();

  static final SocialApiClient instance = SocialApiClient._();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'SOCIAL_BACKEND_URL',
  );
  static const String defaultSocialBackendUrl =
      'https://sudoku-duel-social-staging.ilhanahmet246.workers.dev';

  static const String productionSocialBackendUrl =
      'https://sudoku-duel-social-production.ilhanahmet246.workers.dev';

  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _appCheckTimeout = Duration(seconds: 15);

  final http.Client _client = http.Client();

  static String get _baseUrl => resolveBaseUrlForTest(
    configuredBaseUrl: _configuredBaseUrl,
    debugMode: kDebugMode,
  );

  @visibleForTesting
  static String resolveBaseUrlForTest({
    required String configuredBaseUrl,
    required bool debugMode,
  }) {
    final configured = configuredBaseUrl.trim();

    final selected = configured.isNotEmpty
        ? configured
        : (debugMode ? defaultSocialBackendUrl : productionSocialBackendUrl);

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

  bool get usingBundledDefault => _configuredBaseUrl.trim().isEmpty;

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
      body: <String, Object>{'variant': variant, 'difficulty': difficulty},
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

    final user = await FirebaseSessionService.ensureAnonymousSession();

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
      'x-firebase-appcheck': appCheckToken,
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

  Future<String> _appCheckToken() async {
    try {
      return await FirebaseServices.instance.requireAppCheckToken(
        timeout: _appCheckTimeout,
      );
    } on TimeoutException {
      throw const SocialApiException(
        403,
        'App Check verification timed out. Please try again.',
      );
    } on SocialApiException {
      rethrow;
    } catch (error) {
      debugPrint('Social API App Check unavailable: ${error.runtimeType}');

      throw const SocialApiException(
        403,
        'App Check could not verify this installation.',
      );
    }
  }
}
