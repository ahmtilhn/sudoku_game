import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firebase_session_service.dart';
import 'social_api_client.dart';

class EconomyApiException implements Exception {
  const EconomyApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  bool get isInsufficientCoins => code == 'insufficient_coins';

  @override
  String toString() => '$statusCode: $message';
}

class WalletSnapshot {
  const WalletSnapshot({
    required this.balance,
    required this.canEnterOnline,
    required this.minimumOnlineBalance,
    required this.entryFees,
    required this.noAds,
    required this.starterGrant,
    required this.dailyLoginAmount,
    required this.dailyLoginAvailable,
    required this.dailyAdAmount,
    required this.dailyAdAvailable,
    this.nextDailyResetAt,
  });

  final int balance;
  final bool canEnterOnline;
  final int minimumOnlineBalance;
  final Map<String, int> entryFees;
  final bool noAds;
  final int starterGrant;
  final int dailyLoginAmount;
  final bool dailyLoginAvailable;
  final int dailyAdAmount;
  final bool dailyAdAvailable;
  final DateTime? nextDailyResetAt;

  int get entryFee => entryFeeForDifficulty('beginner');
  int get winnerPot => winnerPotForDifficulty('beginner');

  int entryFeeForDifficulty(String difficulty) {
    return entryFees[difficulty.toLowerCase()] ??
        entryFees['beginner'] ??
        minimumOnlineBalance;
  }

  int winnerPotForDifficulty(String difficulty) {
    return entryFeeForDifficulty(difficulty) * 2;
  }

  factory WalletSnapshot.fromJson(Map<String, dynamic> json) {
    final login =
        (json['dailyLogin'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final ad =
        (json['dailyRewardedAd'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rawEntryFees = (json['entryFees'] as Map?)?.cast<String, dynamic>();
    final entryFees = <String, int>{
      if (rawEntryFees != null)
        for (final item in rawEntryFees.entries)
          item.key.toLowerCase(): (item.value as num?)?.toInt() ?? 0,
    }..removeWhere((_, value) => value <= 0);
    final legacyEntryFee = (json['entryFee'] as num?)?.toInt();
    if (entryFees.isEmpty && legacyEntryFee != null && legacyEntryFee > 0) {
      entryFees['beginner'] = legacyEntryFee;
    }
    entryFees.putIfAbsent(
      'beginner',
      () => (json['minimumOnlineBalance'] as num?)?.toInt() ?? 100,
    );
    final entitlements =
        (json['entitlements'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return WalletSnapshot(
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      canEnterOnline: json['canEnterOnline'] == true,
      minimumOnlineBalance:
          (json['minimumOnlineBalance'] as num?)?.toInt() ?? 100,
      entryFees: Map<String, int>.unmodifiable(entryFees),
      noAds: entitlements['noAds'] == true,
      starterGrant: (json['starterGrant'] as num?)?.toInt() ?? 1000,
      dailyLoginAmount: (login['amount'] as num?)?.toInt() ?? 50,
      dailyLoginAvailable: login['available'] == true,
      dailyAdAmount: (ad['amount'] as num?)?.toInt() ?? 50,
      dailyAdAvailable: ad['available'] == true,
      nextDailyResetAt: DateTime.tryParse(
        json['nextDailyResetAt']?.toString() ?? '',
      ),
    );
  }
}

class CoinLedgerEntry {
  const CoinLedgerEntry({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    required this.reason,
    required this.createdAt,
    this.referenceType,
    this.referenceId,
  });

  final String id;
  final int amount;
  final int balanceAfter;
  final String reason;
  final String? referenceType;
  final String? referenceId;
  final DateTime createdAt;

  factory CoinLedgerEntry.fromJson(Map<String, dynamic> json) {
    return CoinLedgerEntry(
      id: json['id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
      reason: json['reason']?.toString() ?? 'unknown',
      referenceType: json['referenceType']?.toString(),
      referenceId: json['referenceId']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PreparedCoinReward {
  const PreparedCoinReward({
    required this.token,
    required this.rewardType,
    required this.rewardKey,
    required this.amount,
    required this.expiresAt,
  });

  final String token;
  final String rewardType;
  final String rewardKey;
  final int amount;
  final DateTime expiresAt;

  factory PreparedCoinReward.fromJson(Map<String, dynamic> json) {
    return PreparedCoinReward(
      token: json['token']?.toString() ?? '',
      rewardType: json['rewardType']?.toString() ?? '',
      rewardKey: json['rewardKey']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class RematchPerson {
  const RematchPerson({required this.publicId, required this.displayName});

  final String publicId;
  final String displayName;

  factory RematchPerson.fromJson(Map<String, dynamic> json) {
    return RematchPerson(
      publicId: json['publicId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Sudoku Player',
    );
  }
}

class RematchInvitation {
  const RematchInvitation({
    required this.id,
    required this.previousMatchId,
    required this.difficulty,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.isSender,
    required this.sender,
    required this.recipient,
    this.roomId,
  });

  final String id;
  final String previousMatchId;
  final String difficulty;
  final String status;
  final String? roomId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isSender;
  final RematchPerson sender;
  final RematchPerson recipient;

  bool get isPending => status == 'pending';

  factory RematchInvitation.fromJson(Map<String, dynamic> json) {
    return RematchInvitation(
      id: json['id']?.toString() ?? '',
      previousMatchId: json['previousMatchId']?.toString() ?? '',
      difficulty: json['difficulty']?.toString() ?? 'easy',
      status: json['status']?.toString() ?? 'pending',
      roomId: json['roomId']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
      isSender: json['isSender'] == true,
      sender: RematchPerson.fromJson(
        (json['sender'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      recipient: RematchPerson.fromJson(
        (json['recipient'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class EconomyApiClient {
  EconomyApiClient._();

  static final EconomyApiClient instance = EconomyApiClient._();
  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _appCheckTimeout = Duration(seconds: 5);

  final http.Client _client = http.Client();

  Future<WalletSnapshot> loadWallet() async {
    return WalletSnapshot.fromJson(await _request('GET', '/v1/me/wallet'));
  }

  Future<List<CoinLedgerEntry>> loadLedger({int limit = 50}) async {
    final response = await _request(
      'GET',
      '/v1/me/wallet/ledger?limit=${limit.clamp(1, 100)}',
    );
    final entries = response['entries'];
    if (entries is! List) return const <CoinLedgerEntry>[];
    return entries
        .whereType<Map>()
        .map((entry) => CoinLedgerEntry.fromJson(entry.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<WalletSnapshot> claimDailyLogin() async {
    return WalletSnapshot.fromJson(
      await _request('POST', '/v1/rewards/daily-login/claim'),
    );
  }

  Future<PreparedCoinReward> prepareDailyAd() async {
    return PreparedCoinReward.fromJson(
      await _request('POST', '/v1/rewards/daily-ad/prepare'),
    );
  }

  Future<PreparedCoinReward> prepareCareerAd() async {
    return PreparedCoinReward.fromJson(
      await _request('POST', '/v1/rewards/career-ad/prepare'),
    );
  }

  Future<WalletSnapshot> confirmDailyAd(String token) async {
    return WalletSnapshot.fromJson(
      await _request(
        'POST',
        '/v1/rewards/daily-ad/confirm',
        body: <String, Object>{'token': token},
      ),
    );
  }

  Future<WalletSnapshot> confirmCareerAd(String token) async {
    return WalletSnapshot.fromJson(
      await _request(
        'POST',
        '/v1/rewards/career-ad/confirm',
        body: <String, Object>{'token': token},
      ),
    );
  }

  Future<WalletSnapshot> spendCareerContinue(String requestId) async {
    return WalletSnapshot.fromJson(
      await _request(
        'POST',
        '/v1/me/wallet/spend/career-continue',
        body: <String, Object>{'requestId': requestId},
      ),
    );
  }

  Future<WalletSnapshot> claimAchievement(String achievementId) async {
    return WalletSnapshot.fromJson(
      await _request(
        'POST',
        '/v1/achievements/${Uri.encodeComponent(achievementId)}/claim',
      ),
    );
  }

  Future<RematchInvitation> createRematch(String matchId) async {
    return RematchInvitation.fromJson(
      await _request(
        'POST',
        '/v1/matches/${Uri.encodeComponent(matchId)}/rematch',
      ),
    );
  }

  Future<List<RematchInvitation>> loadRematches() async {
    final response = await _request('GET', '/v1/rematches/pending');
    final invitations = response['invitations'];
    if (invitations is! List) return const <RematchInvitation>[];
    return invitations
        .whereType<Map>()
        .map((item) => RematchInvitation.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<RematchInvitation> respondRematch({
    required String invitationId,
    required bool accept,
  }) async {
    return RematchInvitation.fromJson(
      await _request(
        'POST',
        '/v1/rematches/${Uri.encodeComponent(invitationId)}/respond',
        body: <String, Object>{'action': accept ? 'accept' : 'decline'},
      ),
    );
  }

  Future<WalletSnapshot> verifyPurchase({
    required String platform,
    required String productId,
    required String transactionId,
    required String verificationData,
  }) async {
    final path = platform == 'ios'
        ? '/v1/purchases/apple/verify'
        : '/v1/purchases/google/verify';
    return WalletSnapshot.fromJson(
      await _request(
        'POST',
        path,
        body: <String, Object>{
          'productId': productId,
          'transactionId': transactionId,
          'verificationData': verificationData,
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
