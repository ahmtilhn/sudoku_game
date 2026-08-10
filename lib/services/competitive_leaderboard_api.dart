import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'social_api_client.dart';

class CompetitiveLeaderboardEntry {
  const CompetitiveLeaderboardEntry({
    required this.rank,
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.country,
    required this.rating,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.winRate,
    required this.winStreak,
    required this.bestRating,
    required this.provisionalGames,
  });

  final int rank;
  final String publicId;
  final String username;
  final String displayName;
  final String avatarKey;
  final String? country;
  final int rating;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final double winRate;
  final int winStreak;
  final int bestRating;
  final int provisionalGames;

  bool get isProvisional => provisionalGames > 0;

  CompetitiveLeaderboardEntry copyWith({int? rank}) {
    return CompetitiveLeaderboardEntry(
      rank: rank ?? this.rank,
      publicId: publicId,
      username: username,
      displayName: displayName,
      avatarKey: avatarKey,
      country: country,
      rating: rating,
      gamesPlayed: gamesPlayed,
      wins: wins,
      losses: losses,
      draws: draws,
      winRate: winRate,
      winStreak: winStreak,
      bestRating: bestRating,
      provisionalGames: provisionalGames,
    );
  }

  factory CompetitiveLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    final gamesPlayed = _int(json['gamesPlayed']);
    final provisionalGames = json.containsKey('provisionalGames')
        ? _int(json['provisionalGames'])
        : (20 - gamesPlayed).clamp(0, 20).toInt();
    return CompetitiveLeaderboardEntry(
      rank: _int(json['rank'], fallback: 1),
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Sudoku Player',
      avatarKey: json['avatarKey']?.toString() ?? 'default',
      country: _country(json['country']),
      rating: _int(json['rating'], fallback: 1000),
      gamesPlayed: gamesPlayed,
      wins: _int(json['wins']),
      losses: _int(json['losses']),
      draws: _int(json['draws']),
      winRate: _double(json['winRate']),
      winStreak: _int(json['winStreak']),
      bestRating: _int(
        json['bestRating'],
        fallback: _int(json['rating'], fallback: 1000),
      ),
      provisionalGames: provisionalGames,
    );
  }
}

class CompetitiveLeaderboardCurrentPlayer {
  const CompetitiveLeaderboardCurrentPlayer({
    required this.rank,
    required this.rating,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.winRate,
    required this.winStreak,
    required this.bestRating,
    required this.provisionalGames,
  });

  final int? rank;
  final int rating;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final double winRate;
  final int winStreak;
  final int bestRating;
  final int provisionalGames;

  bool get isProvisional => provisionalGames > 0;

  factory CompetitiveLeaderboardCurrentPlayer.fromJson(
    Map<String, dynamic> json,
  ) {
    final gamesPlayed = _int(json['gamesPlayed']);
    final provisionalGames = json.containsKey('provisionalGames')
        ? _int(json['provisionalGames'])
        : 0;
    return CompetitiveLeaderboardCurrentPlayer(
      rank: json['rank'] == null ? null : _int(json['rank']),
      rating: _int(json['rating'], fallback: 1000),
      gamesPlayed: gamesPlayed,
      wins: _int(json['wins']),
      losses: _int(json['losses']),
      draws: _int(json['draws']),
      winRate: _double(json['winRate']),
      winStreak: _int(json['winStreak']),
      bestRating: _int(
        json['bestRating'],
        fallback: _int(json['rating'], fallback: 1000),
      ),
      provisionalGames: provisionalGames,
    );
  }
}

class CompetitiveLeaderboardPage {
  const CompetitiveLeaderboardPage({
    required this.scope,
    required this.variant,
    required this.mode,
    required this.entries,
    required this.currentPlayer,
    required this.nextCursor,
    required this.stale,
  });

  final String scope;
  final String variant;
  final String mode;
  final List<CompetitiveLeaderboardEntry> entries;
  final CompetitiveLeaderboardCurrentPlayer currentPlayer;
  final String? nextCursor;
  final bool stale;

  factory CompetitiveLeaderboardPage.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final current = json['currentPlayer'];
    return CompetitiveLeaderboardPage(
      scope: json['scope']?.toString() ?? 'global',
      variant: json['variant']?.toString() ?? 'classic9',
      mode: json['mode']?.toString() ?? 'top',
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map(
                  (value) => CompetitiveLeaderboardEntry.fromJson(
                    value.cast<String, dynamic>(),
                  ),
                )
                .where((value) => value.publicId.isNotEmpty)
                .toList(growable: false)
          : const <CompetitiveLeaderboardEntry>[],
      currentPlayer: CompetitiveLeaderboardCurrentPlayer.fromJson(
        current is Map
            ? current.cast<String, dynamic>()
            : const <String, dynamic>{},
      ),
      nextCursor: json['nextCursor']?.toString(),
      stale: json['stale'] == true,
    );
  }
}

class CompetitiveLeaderboardApi {
  CompetitiveLeaderboardApi._();

  static final CompetitiveLeaderboardApi instance = CompetitiveLeaderboardApi._();
  static const Duration _timeout = Duration(seconds: 15);

  Future<CompetitiveLeaderboardPage> load({
    required String scope,
    required String variant,
    required String mode,
    String? cursor,
    int limit = 50,
  }) async {
    final social = SocialApiClient.instance;
    if (!social.configured) {
      throw const SocialApiException(
        0,
        'The social backend URL is not configured.',
      );
    }
    if (!_validScope(scope)) {
      throw ArgumentError.value(scope, 'scope', 'Unsupported leaderboard scope.');
    }
    if (variant != 'classic9' && variant != 'classic16') {
      throw ArgumentError.value(variant, 'variant', 'Unsupported Sudoku variant.');
    }
    if (mode != 'top' && mode != 'friends' && mode != 'around_me') {
      throw ArgumentError.value(mode, 'mode', 'Unsupported leaderboard mode.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SocialApiException(401, 'A Firebase session is required.');
    }

    final String? idToken;
    try {
      idToken = await user.getIdToken().timeout(_timeout);
    } on TimeoutException {
      throw const SocialApiException(0, 'Firebase session refresh timed out.');
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

    final query = <String, String>{
      'mode': mode,
      'variant': variant,
      'limit': '${limit.clamp(1, 100)}',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = Uri.parse(
      '${social.baseUrl}/v1/competitive/leaderboards/${Uri.encodeComponent(scope)}',
    ).replace(queryParameters: query);

    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken(false).timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      appCheckToken = null;
    }

    final http.Response response;
    try {
      response = await http
          .get(
            uri,
            headers: <String, String>{
              'authorization': 'Bearer $idToken',
              'accept': 'application/json',
              if (appCheckToken != null && appCheckToken.isNotEmpty)
                'x-firebase-appcheck': appCheckToken,
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const SocialApiException(
        0,
        'The social server did not respond in time.',
      );
    } on http.ClientException catch (error) {
      throw SocialApiException(0, error.message);
    }

    final Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(response.body);
      decoded = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
    } catch (_) {
      throw SocialApiException(
        response.statusCode,
        'The social server returned an invalid response.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SocialApiException(
        response.statusCode,
        decoded['error']?.toString() ?? 'Leaderboard request failed.',
      );
    }
    return CompetitiveLeaderboardPage.fromJson(decoded);
  }

  bool _validScope(String scope) => const <String>{
    'global',
    'beginner',
    'easy',
    'medium',
    'hard',
    'expert',
  }.contains(scope);
}

int _int(Object? value, {int fallback = 0}) =>
    value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? fallback;

double _double(Object? value) =>
    value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;

String? _country(Object? value) {
  final text = value?.toString().trim().toUpperCase();
  return text != null && RegExp(r'^[A-Z]{2}$').hasMatch(text) ? text : null;
}
