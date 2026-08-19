import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/sudoku_variant.dart';
import 'firebase_session_service.dart';
import 'firebase_services.dart';
import 'social_api_client.dart';

class VariantMatchmakingResult {
  const VariantMatchmakingResult({
    required this.status,
    required this.difficulty,
    required this.variant,
    required this.boardSize,
    required this.cellCount,
    this.roomId,
    this.rating,
    this.onlineCoins,
  });

  final String status;
  final String difficulty;
  final SudokuVariant variant;
  final int boardSize;
  final int cellCount;
  final String? roomId;
  final int? rating;
  final int? onlineCoins;

  bool get matched => status == 'matched' && roomId?.isNotEmpty == true;

  factory VariantMatchmakingResult.fromJson(Map<String, dynamic> json) {
    final rawVariant = json['variant']?.toString() ?? 'classic9';
    final SudokuVariant variant;
    try {
      variant = SudokuVariant.fromKey(rawVariant);
    } on ArgumentError {
      throw const FormatException('Unsupported matchmaking variant.');
    }
    final boardSize = (json['boardSize'] as num?)?.toInt() ?? variant.boardSize;
    final cellCount = (json['cellCount'] as num?)?.toInt() ?? variant.cellCount;
    if (boardSize != variant.boardSize || cellCount != variant.cellCount) {
      throw const FormatException(
        'Matchmaking variant metadata is inconsistent.',
      );
    }
    return VariantMatchmakingResult(
      status: json['status']?.toString() ?? 'queued',
      difficulty: json['difficulty']?.toString() ?? 'easy',
      variant: variant,
      boardSize: boardSize,
      cellCount: cellCount,
      roomId: json['roomId']?.toString(),
      rating: (json['rating'] as num?)?.toInt(),
      onlineCoins: (json['onlineCoins'] as num?)?.toInt(),
    );
  }
}

typedef MatchmakingTokenProvider = Future<String> Function();
typedef MatchmakingAppCheckProvider = Future<String> Function();

class VariantMatchmakingClient {
  VariantMatchmakingClient({
    http.Client? client,
    String? baseUrl,
    MatchmakingTokenProvider? tokenProvider,
    MatchmakingAppCheckProvider? appCheckProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? SocialApiClient.instance.baseUrl).trim(),
       _tokenProvider = tokenProvider ?? _firebaseToken,
       _appCheckProvider = appCheckProvider ?? _appCheckToken;

  static final VariantMatchmakingClient instance = VariantMatchmakingClient();
  static const Duration _timeout = Duration(seconds: 15);
  static const Duration _appCheckTimeout = Duration(seconds: 3);

  final http.Client _client;
  final String _baseUrl;
  final MatchmakingTokenProvider _tokenProvider;
  final MatchmakingAppCheckProvider _appCheckProvider;

  bool get configured {
    final uri = Uri.tryParse(_baseUrl);
    return uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' || uri.host == 'localhost');
  }

  static Map<String, Object> queuePayload({
    required String difficulty,
    required SudokuVariant variant,
  }) {
    return <String, Object>{'difficulty': difficulty, ...variant.toJson()};
  }

  Future<VariantMatchmakingResult> joinRankedQueue({
    required String difficulty,
    required SudokuVariant variant,
  }) async {
    final response = await _request(
      'POST',
      body: queuePayload(difficulty: difficulty, variant: variant),
    );
    return VariantMatchmakingResult.fromJson(response);
  }

  Future<void> cancelRankedQueue() async {
    await _request('DELETE');
  }

  Future<Map<String, dynamic>> _request(
    String method, {
    Map<String, Object?>? body,
  }) async {
    if (!configured) {
      throw const SocialApiException(0, 'The social service is unavailable.');
    }

    final token = await _tokenProvider().timeout(_timeout);
    final appCheckToken = await _appCheckProvider().timeout(_timeout);
    final headers = <String, String>{
      'authorization': 'Bearer $token',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (appCheckToken.isNotEmpty) 'x-firebase-appcheck': appCheckToken,
    };
    final uri = Uri.parse('$_baseUrl/v1/matchmaking/queue');
    final Future<http.Response> pending = switch (method) {
      'POST' => _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
      'DELETE' => _client.delete(uri, headers: headers),
      _ => throw ArgumentError.value(method, 'method'),
    };

    final http.Response response;
    try {
      response = await pending.timeout(_timeout);
    } on TimeoutException {
      throw const SocialApiException(
        0,
        'The matchmaking service did not respond in time.',
      );
    } on http.ClientException {
      throw const SocialApiException(
        0,
        'Unable to connect to the matchmaking service.',
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
          'The matchmaking service returned an invalid response.',
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SocialApiException(
        response.statusCode,
        decoded['error']?.toString() ??
            'The matchmaking request could not be completed.',
      );
    }
    return decoded;
  }

  static Future<String> _firebaseToken() async {
    final user = await FirebaseSessionService.ensureAnonymousSession();
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const SocialApiException(401, 'The player session is unavailable.');
    }
    return token;
  }

  static Future<String> _appCheckToken() async {
    return await FirebaseServices.instance.tryGetAppCheckToken(
          timeout: _appCheckTimeout,
        ) ??
        '';
  }
}
