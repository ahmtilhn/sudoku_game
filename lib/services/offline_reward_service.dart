import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../domain/sudoku.dart';
import '../domain/sudoku_variant.dart';
import 'ads_service.dart';
import 'economy_api_client.dart';
import 'economy_service.dart';
import 'firebase_session_service.dart';
import 'firebase_services.dart';
import 'social_api_client.dart';

class OfflineRewardService {
  OfflineRewardService._();

  static final OfflineRewardService instance = OfflineRewardService._();
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client = http.Client();
  final Random _random = Random.secure();

  Future<int> claimQuickPlayCompletion({
    required SudokuPuzzle puzzle,
    required SudokuVariant variant,
  }) async {
    final completionId = <Object>[
      'play',
      DateTime.now().microsecondsSinceEpoch,
      _random.nextInt(1 << 31),
    ].join(':');
    final body = await _request(
      '/v1/economy/v3/play/claim',
      <String, Object>{
        'puzzleId': puzzle.id,
        'completionId': completionId,
        'difficulty': puzzle.difficulty.name,
        'variant': variant.id == SudokuVariantId.classic16
            ? 'classic16'
            : 'classic9',
      },
    );
    await EconomyService.instance.refresh(showLoading: false);
    return (body['amount'] as num?)?.toInt() ?? 0;
  }

  Future<int> doubleCareerReward({
    required int level,
    required SudokuVariant variant,
  }) async {
    if (AdsService.instance.noAds) return 0;
    final variantName = variant.id == SudokuVariantId.classic16
        ? 'classic16'
        : 'classic9';
    final prepared = await _request(
      '/v1/economy/v3/career/double/prepare',
      <String, Object>{'level': level, 'variant': variantName},
    );
    final token = prepared['token']?.toString() ?? '';
    if (token.isEmpty) return 0;
    final earned = await AdsService.instance.showRewarded(
      verificationToken: token,
    );
    if (!earned) return 0;

    final confirmed = await _confirmAfterSsv(token);
    await EconomyService.instance.refresh(showLoading: false);
    return (confirmed['amount'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> _confirmAfterSsv(String token) async {
    const attempts = 8;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await _request(
          '/v1/economy/v3/career/double/confirm',
          <String, Object>{'token': token},
        );
      } on EconomyApiException catch (error) {
        final waiting = error.code == 'reward_waiting_for_ssv';
        if (!waiting || attempt == attempts - 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw StateError('Career double confirmation retry exhausted.');
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, Object> body,
  ) async {
    final social = SocialApiClient.instance;
    if (!social.configured) {
      throw const EconomyApiException(
        0,
        'The economy server URL is not configured.',
      );
    }

    final user = await FirebaseSessionService.ensureAnonymousSession();
    final String? idToken;
    try {
      idToken = await user.getIdToken().timeout(_timeout);
    } on TimeoutException {
      throw const EconomyApiException(0, 'Firebase session refresh timed out.');
    } on FirebaseAuthException catch (error) {
      throw EconomyApiException(
        401,
        error.message ?? 'Unable to refresh the Firebase session.',
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const EconomyApiException(401, 'Unable to obtain a player token.');
    }

    final appCheckToken = await FirebaseServices.instance.tryGetAppCheckToken(
      timeout: _timeout,
    );
    final response = await _client
        .post(
          Uri.parse('${social.baseUrl}$path'),
          headers: <String, String>{
            'authorization': 'Bearer $idToken',
            'accept': 'application/json',
            'content-type': 'application/json',
            if (appCheckToken != null && appCheckToken.isNotEmpty)
              'x-firebase-appcheck': appCheckToken,
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      final value = jsonDecode(response.body);
      if (value is Map) decoded = value.cast<String, dynamic>();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EconomyApiException(
        response.statusCode,
        decoded['error']?.toString() ?? 'Economy request failed.',
        code: decoded['code']?.toString(),
      );
    }
    return decoded;
  }
}
