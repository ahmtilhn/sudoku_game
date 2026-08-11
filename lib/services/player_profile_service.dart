import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'firebase_session_service.dart';
import 'platform_game_services.dart';
import 'platform_profile_policy.dart';
import 'social_api_client.dart';

class PlayerProfileException implements Exception {
  const PlayerProfileException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => message;
}

class PlayerProfilePreferences {
  const PlayerProfilePreferences({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.profileConfirmed,
    required this.discoverable,
    required this.nameSource,
    required this.rating,
    required this.gamesPlayed,
    required this.wins,
    this.platformDisplayName,
    this.avatarUrl,
    this.platformConnected = false,
  });

  final String publicId;
  final String username;
  final String displayName;
  final bool profileConfirmed;
  final bool discoverable;
  final String nameSource;
  final int rating;
  final int gamesPlayed;
  final int wins;
  final String? platformDisplayName;
  final String? avatarUrl;
  final bool platformConnected;

  PlayerProfilePreferences copyWith({
    String? publicId,
    String? username,
    String? displayName,
    bool? profileConfirmed,
    bool? discoverable,
    String? nameSource,
    int? rating,
    int? gamesPlayed,
    int? wins,
    String? platformDisplayName,
    String? avatarUrl,
    bool? platformConnected,
  }) {
    return PlayerProfilePreferences(
      publicId: publicId ?? this.publicId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      profileConfirmed: profileConfirmed ?? this.profileConfirmed,
      discoverable: discoverable ?? this.discoverable,
      nameSource: nameSource ?? this.nameSource,
      rating: rating ?? this.rating,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      wins: wins ?? this.wins,
      platformDisplayName: platformDisplayName ?? this.platformDisplayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      platformConnected: platformConnected ?? this.platformConnected,
    );
  }

  factory PlayerProfilePreferences.fromJson(Map<String, dynamic> json) {
    return PlayerProfilePreferences(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Sudoku Player',
      profileConfirmed: _boolFromJson(json['profileConfirmed']),
      discoverable: _boolFromJson(json['discoverable'], defaultValue: true),
      nameSource: json['nameSource']?.toString() ?? 'generated',
      rating: _intFromJson(json['rating'], defaultValue: 1000),
      gamesPlayed: _intFromJson(json['gamesPlayed']),
      wins: _intFromJson(json['wins']),
      platformDisplayName: json['platformDisplayName']?.toString(),
      avatarUrl: PlatformProfilePolicy.normalizedAvatarUrl(
        json['avatarUrl']?.toString(),
      ),
      platformConnected: _boolFromJson(json['platformConnected']),
    );
  }
}

bool _boolFromJson(Object? value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return defaultValue;
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return defaultValue;
}

int _intFromJson(Object? value, {int defaultValue = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ?? defaultValue;
}

class PlayerProfileService {
  PlayerProfileService._();

  static final PlayerProfileService instance = PlayerProfileService._();
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client = http.Client();
  final ValueNotifier<PlayerProfilePreferences?> current =
      ValueNotifier<PlayerProfilePreferences?>(null);

  Future<PlayerProfilePreferences> load() async {
    final player = await _loadPlatformPlayer();
    final platformName = player?.effectiveDisplayName.trim();
    final platformSource = player?.platform ?? 'google_play_games';
    final platformAvatar = PlatformProfilePolicy.normalizedAvatarUrl(
      player?.avatarUrl,
    );
    final platformConnected =
        player != null && player.playerId.trim().isNotEmpty;

    PlayerProfilePreferences preferences;
    try {
      preferences = await _loadRemotePreferences();
    } catch (firstError, firstStackTrace) {
      if (platformName != null &&
          platformName.isNotEmpty &&
          SocialApiClient.instance.configured) {
        try {
          await SocialApiClient.instance.ensureProfile(
            displayName: platformName,
          );
          preferences = await _loadRemotePreferences();
        } catch (_) {
          final fallback = PlayerProfilePreferences(
            publicId: '',
            username: '',
            displayName: platformName,
            profileConfirmed: false,
            discoverable: true,
            nameSource: platformSource,
            rating: 1000,
            gamesPlayed: 0,
            wins: 0,
            platformDisplayName: platformName,
            avatarUrl: platformAvatar,
            platformConnected: platformConnected,
          );
          current.value = fallback;
          return fallback;
        }
      } else {
        Error.throwWithStackTrace(firstError, firstStackTrace);
      }
    }

    if (platformName == null || platformName.isEmpty) {
      current.value = preferences.copyWith(platformConnected: false);
      return current.value!;
    }

    final decision = PlatformProfilePolicy.decideNameUpdate(
      profileConfirmed: preferences.profileConfirmed,
      currentNameSource: preferences.nameSource,
      currentDisplayName: preferences.displayName,
      platformDisplayName: platformName,
    );

    if (decision == PlatformProfileNameDecision.adoptPlatform &&
        preferences.username.trim().isNotEmpty) {
      try {
        preferences = await update(
          username: preferences.username,
          displayName: platformName,
          discoverable: preferences.discoverable,
          nameSource: platformSource,
        );
      } catch (_) {
        preferences = preferences.copyWith(
          displayName: platformName,
          nameSource: platformSource,
        );
      }
    } else if (decision == PlatformProfileNameDecision.adoptPlatform) {
      preferences = preferences.copyWith(
        displayName: platformName,
        nameSource: platformSource,
      );
    }

    preferences = preferences.copyWith(
      platformDisplayName: platformName,
      avatarUrl: platformAvatar,
      platformConnected: platformConnected,
    );
    current.value = preferences;
    return preferences;
  }

  Future<PlayerProfilePreferences> refreshFromPlatform() => load();

  Future<PlayerProfilePreferences> _loadRemotePreferences() async {
    return PlayerProfilePreferences.fromJson(
      await _request('GET', '/v1/me/preferences'),
    );
  }

  Future<PlatformPlayer?> _loadPlatformPlayer() async {
    final games = PlatformGameServices.instance;
    final cached = games.localPlayer.value;
    if (cached != null) return cached;

    try {
      if (!await games.isConfigured()) return null;
      final authenticated = await games.refreshAuthentication();
      return authenticated ? games.localPlayer.value : null;
    } on PlatformGameServicesException {
      return null;
    }
  }

  Future<PlayerProfilePreferences> update({
    required String username,
    required String displayName,
    required bool discoverable,
    required String nameSource,
  }) async {
    final platformMetadata = current.value;
    final updated =
        PlayerProfilePreferences.fromJson(
          await _request(
            'PUT',
            '/v1/me/preferences',
            body: <String, Object>{
              'username': username.trim().toLowerCase(),
              'displayName': displayName.trim(),
              'discoverable': discoverable,
              'nameSource': nameSource,
            },
          ),
        ).copyWith(
          platformDisplayName: platformMetadata?.platformDisplayName,
          avatarUrl: platformMetadata?.avatarUrl,
          platformConnected: platformMetadata?.platformConnected,
        );
    current.value = updated;
    return updated;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final social = SocialApiClient.instance;
    if (!social.configured) {
      throw const PlayerProfileException(
        0,
        'The player profile server is not configured.',
      );
    }
    final user = await FirebaseSessionService.ensureAnonymousSession();
    final String? idToken;
    try {
      idToken = await user.getIdToken().timeout(_timeout);
    } on TimeoutException {
      throw const PlayerProfileException(
        0,
        'Player session refresh timed out.',
      );
    } on FirebaseAuthException catch (error) {
      throw PlayerProfileException(
        401,
        error.message ?? 'Unable to refresh the player session.',
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const PlayerProfileException(
        401,
        'Unable to obtain a player token.',
      );
    }

    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance
          .getToken(false)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      appCheckToken = null;
    }

    final uri = Uri.parse('${social.baseUrl}$path');
    final headers = <String, String>{
      'authorization': 'Bearer $idToken',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (appCheckToken != null && appCheckToken.isNotEmpty)
        'x-firebase-appcheck': appCheckToken,
    };
    final pending = method == 'GET'
        ? _client.get(uri, headers: headers)
        : _client.put(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const <String, Object?>{}),
          );

    final http.Response response;
    try {
      response = await pending.timeout(_timeout);
    } on TimeoutException {
      throw const PlayerProfileException(
        0,
        'The player profile server did not respond in time.',
      );
    } on http.ClientException catch (error) {
      throw PlayerProfileException(0, error.message);
    }

    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        final value = jsonDecode(response.body);
        if (value is Map) decoded = value.cast<String, dynamic>();
      } catch (_) {
        throw PlayerProfileException(
          response.statusCode,
          'The player profile server returned an invalid response.',
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlayerProfileException(
        response.statusCode,
        decoded['error']?.toString() ?? 'Player profile request failed.',
        code: decoded['code']?.toString(),
      );
    }
    return decoded;
  }
}
