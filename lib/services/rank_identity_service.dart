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

  Future<RankIdentityProfile> save({
    String? avatarKey,
    String? frameKey,
    String? titleKey,
    List<String>? achievementIds,
  }) async {
    final body = <String, Object?>{
      if (avatarKey != null) 'avatarKey': avatarKey,
      if (frameKey != null) 'frameKey': frameKey,
      if (titleKey != null) 'titleKey': titleKey,
      if (achievementIds != null) 'achievementIds': achievementIds,
    };
    final value = RankIdentityProfile.fromJson(
      await _request('PUT', '/v1/me/rank-profile', body: body),
    );
    current.value = value;
    return value;
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
        error.message.isEmpty ? 'Unable to connect to the rank server.' : error.message,
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
