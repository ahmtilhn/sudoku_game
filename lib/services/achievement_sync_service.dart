import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'firebase_services.dart';
import 'firebase_session_service.dart';
import 'platform_game_services.dart';
import 'social_api_client.dart';

/// Mirrors server-authoritative achievements to the platform service.
///
/// Google Play currently has exactly one exported achievement for this app:
/// `achievement_first_victory`. The server is the source of truth for whether
/// it is earned; local Sudoku completion must never unlock it directly.
class AchievementSyncService {
  AchievementSyncService._();

  static final AchievementSyncService instance = AchievementSyncService._();

  static const Duration _timeout = Duration(seconds: 15);

  // Exported from the same Play Games project as android games-ids.xml.
  // Keep the contract test in sync if Play Console ever replaces this ID.
  static const String googlePlayFirstWinAchievementId =
      'CgkIzMyzm9saEAIQSg';

  final http.Client _client = http.Client();
  Future<bool>? _inFlight;
  bool _platformConfirmed = false;

  Future<bool> syncNow({bool retryForSettlement = false}) {
    final pending = _inFlight;
    if (pending != null) return pending;
    final operation = _syncNow(
      retryForSettlement: retryForSettlement,
    ).whenComplete(() => _inFlight = null);
    _inFlight = operation;
    return operation;
  }

  Future<bool> _syncNow({required bool retryForSettlement}) async {
    if (_platformConfirmed) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;

    final games = PlatformGameServices.instance;
    if (!await games.isConfigured()) return false;
    if (!await games.refreshAuthentication()) return false;

    final attempts = retryForSettlement ? 4 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final unlocked = await _serverFirstWinUnlocked();
      if (unlocked) {
        final confirmed = await games.unlockAchievement(
          achievementId: googlePlayFirstWinAchievementId,
        );
        if (confirmed) {
          _platformConfirmed = true;
          return true;
        }
        return false;
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    return false;
  }

  Future<bool> _serverFirstWinUnlocked() async {
    final social = SocialApiClient.instance;
    if (!social.configured) return false;

    final user = await FirebaseSessionService.ensureAnonymousSession();
    final String? idToken;
    try {
      idToken = await user.getIdToken().timeout(_timeout);
    } on TimeoutException {
      return false;
    } on FirebaseAuthException {
      return false;
    }
    if (idToken == null || idToken.isEmpty) return false;

    final appCheckToken = await FirebaseServices.instance.tryGetAppCheckToken(
      timeout: _timeout,
    );
    final uri = Uri.parse('${social.baseUrl}/v1/achievements');
    final headers = <String, String>{
      'authorization': 'Bearer $idToken',
      'accept': 'application/json',
      if (appCheckToken != null && appCheckToken.isNotEmpty)
        'x-firebase-appcheck': appCheckToken,
    };

    try {
      final response = await _client.get(uri, headers: headers).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return false;
      final achievements = decoded['achievements'];
      if (achievements is! List) return false;
      for (final item in achievements.whereType<Map>()) {
        if (item['id']?.toString() == 'first_win') {
          return item['unlocked'] == true;
        }
      }
      return false;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    } on FormatException {
      return false;
    }
  }
}
