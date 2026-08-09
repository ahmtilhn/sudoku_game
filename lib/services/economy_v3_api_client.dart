import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'economy_api_client.dart';
import 'firebase_session_service.dart';
import 'social_api_client.dart';

class EconomyV3Reward {
  const EconomyV3Reward({required this.kind, required this.amount});

  final String kind;
  final int amount;

  bool get isCoin => kind == 'coin';
  bool get isHintRefill => kind == 'hint_refill';

  factory EconomyV3Reward.fromJson(Map<String, dynamic> json) {
    return EconomyV3Reward(
      kind: json['kind']?.toString() ?? 'coin',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }
}

class EconomyV3State {
  const EconomyV3State({
    required this.balance,
    required this.dailyCycleDay,
    required this.dailyAvailable,
    required this.nextReward,
    required this.canDoubleLastCoinReward,
    required this.calendar,
    required this.hintRefills,
    required this.hintRefillSize,
    required this.hintCoinCost,
    required this.careerDailyCap,
    required this.careerEarnedToday,
    required this.careerRemainingToday,
    required this.recoveryEarnedToday,
    required this.recoveryPopupCountToday,
    required this.recoveryDailyCoinCap,
    required this.recoveryDailyPopupCap,
  });

  final int balance;
  final int dailyCycleDay;
  final bool dailyAvailable;
  final EconomyV3Reward nextReward;
  final bool canDoubleLastCoinReward;
  final List<EconomyV3Reward> calendar;
  final int hintRefills;
  final int hintRefillSize;
  final int hintCoinCost;
  final int careerDailyCap;
  final int careerEarnedToday;
  final int careerRemainingToday;
  final int recoveryEarnedToday;
  final int recoveryPopupCountToday;
  final int recoveryDailyCoinCap;
  final int recoveryDailyPopupCap;

  factory EconomyV3State.fromJson(Map<String, dynamic> json) {
    final daily =
        (json['daily'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final inventory =
        (json['inventory'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final career =
        (json['career'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final recovery =
        (json['recovery'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final calendarRaw = daily['calendar'];
    final calendar = calendarRaw is List
        ? calendarRaw
              .whereType<Map>()
              .map(
                (item) => EconomyV3Reward.fromJson(
                  item.cast<String, dynamic>(),
                ),
              )
              .toList(growable: false)
        : const <EconomyV3Reward>[];
    final nextRewardMap =
        (daily['nextReward'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{'kind': 'coin', 'amount': 0};
    return EconomyV3State(
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      dailyCycleDay: (daily['cycleDay'] as num?)?.toInt() ?? 1,
      dailyAvailable: daily['available'] == true,
      nextReward: EconomyV3Reward.fromJson(nextRewardMap),
      canDoubleLastCoinReward: daily['canDoubleLastCoinReward'] == true,
      calendar: calendar,
      hintRefills: (inventory['hintRefills'] as num?)?.toInt() ?? 0,
      hintRefillSize: (inventory['hintRefillSize'] as num?)?.toInt() ?? 3,
      hintCoinCost: (inventory['hintCoinCost'] as num?)?.toInt() ?? 25,
      careerDailyCap: (career['dailyCap'] as num?)?.toInt() ?? 250,
      careerEarnedToday: (career['earnedToday'] as num?)?.toInt() ?? 0,
      careerRemainingToday: (career['remainingToday'] as num?)?.toInt() ?? 0,
      recoveryEarnedToday: (recovery['earnedToday'] as num?)?.toInt() ?? 0,
      recoveryPopupCountToday:
          (recovery['popupCountToday'] as num?)?.toInt() ?? 0,
      recoveryDailyCoinCap:
          (recovery['dailyCoinCap'] as num?)?.toInt() ?? 150,
      recoveryDailyPopupCap:
          (recovery['dailyPopupCap'] as num?)?.toInt() ?? 3,
    );
  }
}

class EconomyV3ClaimResult {
  const EconomyV3ClaimResult({
    required this.state,
    required this.granted,
    this.reward,
    this.amount = 0,
    this.cycleDay,
    this.difficulty,
  });

  final EconomyV3State state;
  final bool granted;
  final EconomyV3Reward? reward;
  final int amount;
  final int? cycleDay;
  final String? difficulty;

  factory EconomyV3ClaimResult.fromJson(Map<String, dynamic> json) {
    final rewardMap = (json['reward'] as Map?)?.cast<String, dynamic>();
    return EconomyV3ClaimResult(
      state: EconomyV3State.fromJson(json),
      granted:
          json['granted'] == true ||
          json['grantedHint'] == true ||
          json['consumed'] == true,
      reward: rewardMap == null ? null : EconomyV3Reward.fromJson(rewardMap),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      cycleDay: (json['cycleDay'] as num?)?.toInt(),
      difficulty: json['difficulty']?.toString(),
    );
  }
}

class EconomyV3Preparation {
  const EconomyV3Preparation({
    required this.token,
    required this.amount,
    this.expiresAt,
  });

  final String token;
  final int amount;
  final DateTime? expiresAt;

  factory EconomyV3Preparation.fromJson(Map<String, dynamic> json) {
    return EconomyV3Preparation(
      token: json['token']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
    );
  }
}

class EconomyV3RecoveryOffer {
  const EconomyV3RecoveryOffer({
    required this.eligible,
    required this.amount,
    this.token,
    this.trigger,
    this.code,
  });

  final bool eligible;
  final int amount;
  final String? token;
  final String? trigger;
  final String? code;

  factory EconomyV3RecoveryOffer.fromJson(Map<String, dynamic> json) {
    return EconomyV3RecoveryOffer(
      eligible: json['eligible'] == true,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      token: json['token']?.toString(),
      trigger: json['trigger']?.toString(),
      code: json['code']?.toString(),
    );
  }
}

class EconomyV3ApiClient {
  EconomyV3ApiClient._();

  static final EconomyV3ApiClient instance = EconomyV3ApiClient._();
  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _appCheckTimeout = Duration(seconds: 5);

  final http.Client _client = http.Client();

  Future<EconomyV3State> loadState() async {
    return EconomyV3State.fromJson(
      await _request('GET', '/v1/economy/v3/state'),
    );
  }

  Future<EconomyV3ClaimResult> claimDaily() async {
    return EconomyV3ClaimResult.fromJson(
      await _request('POST', '/v1/economy/v3/daily/claim'),
    );
  }

  Future<EconomyV3Preparation> prepareDailyDouble() async {
    return EconomyV3Preparation.fromJson(
      await _request('POST', '/v1/economy/v3/daily/double/prepare'),
    );
  }

  Future<EconomyV3ClaimResult> confirmDailyDouble(String token) async {
    return EconomyV3ClaimResult.fromJson(
      await _request(
        'POST',
        '/v1/economy/v3/daily/double/confirm',
        body: <String, Object>{'token': token},
      ),
    );
  }

  Future<EconomyV3ClaimResult> claimCareer({
    required int level,
    required String variant,
  }) async {
    return EconomyV3ClaimResult.fromJson(
      await _request(
        'POST',
        '/v1/economy/v3/career/claim',
        body: <String, Object>{'level': level, 'variant': variant},
      ),
    );
  }

  Future<EconomyV3ClaimResult> purchaseHint(String requestId) async {
    return EconomyV3ClaimResult.fromJson(
      await _request(
        'POST',
        '/v1/economy/v3/hints/purchase',
        body: <String, Object>{'requestId': requestId},
      ),
    );
  }

  Future<EconomyV3Preparation> prepareHintReward() async {
    return EconomyV3Preparation.fromJson(
      await _request('POST', '/v1/economy/v3/hints/reward/prepare'),
    );
  }

  Future<EconomyV3ClaimResult> confirmHintReward(String token) async {
    return EconomyV3ClaimResult.fromJson(
      await _request(
        'POST',
        '/v1/economy/v3/hints/reward/confirm',
        body: <String, Object>{'token': token},
      ),
    );
  }

  Future<EconomyV3ClaimResult> consumeHintRefill() async {
    return EconomyV3ClaimResult.fromJson(
      await _request('POST', '/v1/economy/v3/hints/refill/consume'),
    );
  }

  Future<EconomyV3RecoveryOffer> prepareRecovery(String matchId) async {
    return EconomyV3RecoveryOffer.fromJson(
      await _request(
        'POST',
        '/v1/economy/v3/recovery/prepare',
        body: <String, Object>{'matchId': matchId},
      ),
    );
  }

  Future<EconomyV3ClaimResult> confirmRecovery(String token) async {
    return EconomyV3ClaimResult.fromJson(
      await _request(
        'POST',
        '/v1/economy/v3/recovery/confirm',
        body: <String, Object>{'token': token},
      ),
    );
  }

  Future<void> dismissRecovery(String matchId) async {
    await _request(
      'POST',
      '/v1/economy/v3/recovery/dismiss',
      body: <String, Object>{'matchId': matchId},
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
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

    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance
          .getToken(false)
          .timeout(_appCheckTimeout);
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

    final Future<http.Response> pending = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(
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
      throw const EconomyApiException(
        0,
        'The economy server did not respond in time.',
      );
    } on http.ClientException catch (error) {
      throw EconomyApiException(0, error.message);
    }

    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        final value = jsonDecode(response.body);
        if (value is Map) decoded = value.cast<String, dynamic>();
      } catch (_) {
        throw EconomyApiException(
          response.statusCode,
          'The economy server returned an invalid response.',
        );
      }
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
