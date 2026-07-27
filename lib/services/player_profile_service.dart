import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firebase_session_service.dart';
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

  factory PlayerProfilePreferences.fromJson(Map<String, dynamic> json) {
    return PlayerProfilePreferences(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Sudoku Player',
      profileConfirmed: json['profileConfirmed'] == true,
      discoverable: json['discoverable'] != false,
      nameSource: json['nameSource']?.toString() ?? 'generated',
      rating: (json['rating'] as num?)?.toInt() ?? 1000,
      gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlayerProfileService {
  PlayerProfileService._();

  static final PlayerProfileService instance = PlayerProfileService._();
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client = http.Client();

  Future<PlayerProfilePreferences> load() async {
    return PlayerProfilePreferences.fromJson(
      await _request('GET', '/v1/me/preferences'),
    );
  }

  Future<PlayerProfilePreferences> update({
    required String username,
    required String displayName,
    required bool discoverable,
    required String nameSource,
  }) async {
    return PlayerProfilePreferences.fromJson(
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
    );
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
      throw const PlayerProfileException(0, 'Player session refresh timed out.');
    } on FirebaseAuthException catch (error) {
      throw PlayerProfileException(
        401,
        error.message ?? 'Unable to refresh the player session.',
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const PlayerProfileException(401, 'Unable to obtain a player token.');
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
