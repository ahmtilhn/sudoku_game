import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
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

class SocialChallenge {
  const SocialChallenge({
    required this.id,
    required this.difficulty,
    required this.status,
    required this.challenger,
    required this.recipient,
    required this.expiresAt,
    this.roomId,
  });

  final String id;
  final String difficulty;
  final String status;
  final SocialPlayer challenger;
  final SocialPlayer recipient;
  final DateTime expiresAt;
  final String? roomId;

  factory SocialChallenge.fromJson(Map<String, dynamic> json) {
    return SocialChallenge(
      id: json['id']?.toString() ?? '',
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
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
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

  static const String _baseUrl = String.fromEnvironment('SOCIAL_BACKEND_URL');

  final http.Client _client = http.Client();

  bool get configured => _baseUrl.startsWith('https://');

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
      body: <String, Object>{
        'token': token,
        'platform': platform,
      },
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
  }) async {
    final response = await _request(
      'POST',
      '/v1/challenges',
      body: <String, Object>{
        'recipientPublicId': recipientPublicId,
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
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const SocialApiException(
        401,
        'Unable to obtain a Firebase ID token.',
      );
    }

    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'authorization': 'Bearer $idToken',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
    };

    final response = switch (method) {
      'GET' => await _client.get(uri, headers: headers),
      'POST' => await _client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const <String, Object?>{}),
        ),
      'PUT' => await _client.put(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const <String, Object?>{}),
        ),
      _ => throw ArgumentError.value(method, 'method'),
    };

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(response.body) as Map).cast<String, dynamic>();
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
}
