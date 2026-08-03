import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_player_identity.dart';

class PlatformPlayer {
  const PlatformPlayer({
    required this.platform,
    required this.playerId,
    required this.displayName,
    this.alias,
    this.avatarUrl,
  });

  final String platform;
  final String playerId;
  final String displayName;
  final String? alias;
  final String? avatarUrl;

  PlatformPlayerIdentity toIdentity({bool authenticated = true}) {
    return PlatformPlayerIdentity(
      platform: platform,
      platformPlayerId: playerId,
      displayName: displayName,
      authenticated: authenticated,
      avatarUrl: avatarUrl,
      lastUpdatedAt: DateTime.now(),
    );
  }

  factory PlatformPlayer.fromMap(Map<Object?, Object?> map) {
    return PlatformPlayer(
      platform: map['platform']?.toString() ?? 'unknown',
      playerId: map['playerId']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? 'Player',
      alias: map['alias']?.toString(),
      avatarUrl: map['avatarUrl']?.toString(),
    );
  }
}

class GameCenterIdentityProof {
  const GameCenterIdentityProof({
    required this.gamePlayerId,
    required this.displayName,
    required this.publicKeyUrl,
    required this.signature,
    required this.salt,
    required this.timestamp,
    this.bundleId,
  });

  final String gamePlayerId;
  final String displayName;
  final String publicKeyUrl;
  final String signature;
  final String salt;
  final int timestamp;
  final String? bundleId;

  bool get hasSignatureMaterial =>
      gamePlayerId.trim().isNotEmpty &&
      publicKeyUrl.trim().isNotEmpty &&
      signature.trim().isNotEmpty &&
      salt.trim().isNotEmpty &&
      timestamp > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': 'game_center',
    'platformPlayerId': gamePlayerId,
    'displayName': displayName,
    'publicKeyUrl': publicKeyUrl,
    'signatureBase64': signature,
    'saltBase64': salt,
    'timestampMs': timestamp,
    if (bundleId != null) 'bundleId': bundleId,
  };

  factory GameCenterIdentityProof.fromMap(Map<Object?, Object?> map) {
    return GameCenterIdentityProof(
      gamePlayerId:
          map['gamePlayerId']?.toString() ??
          map['platformPlayerId']?.toString() ??
          '',
      displayName: map['displayName']?.toString() ?? 'Player',
      publicKeyUrl: map['publicKeyUrl']?.toString() ?? '',
      signature: map['signature']?.toString() ?? '',
      salt: map['salt']?.toString() ?? '',
      timestamp: _intFromMap(map['timestampMs'] ?? map['timestamp']),
      bundleId: map['bundleId']?.toString(),
    );
  }
}

class PlatformGameServicesException implements Exception {
  const PlatformGameServicesException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class PlatformGameServices {
  PlatformGameServices._();

  static final PlatformGameServices instance = PlatformGameServices._();

  static const MethodChannel _channel = MethodChannel(
    'com.devoviastudio.sudoku/game_services',
  );

  final ValueNotifier<bool> authenticated = ValueNotifier<bool>(false);
  final ValueNotifier<PlatformPlayer?> localPlayer =
      ValueNotifier<PlatformPlayer?>(null);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  Future<bool> isConfigured() => _invokeBool('isConfigured');

  Future<bool> refreshAuthentication() async {
    final value = await _invokeBool('isAuthenticated');
    authenticated.value = value;
    if (value) {
      localPlayer.value = await getLocalPlayer();
    } else {
      localPlayer.value = null;
    }
    return value;
  }

  Future<bool> authenticate() async {
    final value = await _invokeBool('authenticate');
    authenticated.value = value;
    localPlayer.value = value ? await getLocalPlayer() : null;
    if (!value) {
      lastError.value =
          'authentication_failed: Google Play Games did not authenticate the current account.';
    }
    return value;
  }

  Future<PlatformPlayer?> getLocalPlayer() async {
    final map = await _invokeMap('getLocalPlayer');
    if (map == null) return null;
    return PlatformPlayer.fromMap(map);
  }

  Future<List<PlatformPlayer>> loadFriends() => _loadPlayers('loadFriends');

  Future<List<PlatformPlayer>> loadRecentPlayers() =>
      _loadPlayers('loadRecentPlayers');

  Future<bool> showFriends() => _invokeBool('showFriends');

  Future<bool> showPlayerProfile(String playerId) =>
      _invokeBool('showPlayerProfile', <String, Object>{'playerId': playerId});

  Future<bool> showAchievements() => _invokeBool('showAchievements');

  Future<bool> showLeaderboard({String? leaderboardId}) => _invokeBool(
    'showLeaderboard',
    <String, Object?>{'leaderboardId': leaderboardId},
  );

  Future<bool> submitScore({required int score, String? leaderboardId}) =>
      _invokeBool('submitScore', <String, Object?>{
        'leaderboardId': leaderboardId,
        'score': score,
      });

  Future<bool> unlockAchievement({String? achievementId}) => _invokeBool(
    'unlockAchievement',
    <String, Object?>{'achievementId': achievementId},
  );

  Future<bool> recordGameStatsEvents(
    List<Map<String, Object?>> events,
  ) => _invokeBool('recordGameStatsEvents', <String, Object?>{
    'events': events,
  });

  Future<String?> requestServerAuthCode() async {
    final value = await _invoke<Object?>('requestServerAuthCode');
    return value?.toString();
  }

  Future<GameCenterIdentityProof?> requestGameCenterIdentityProof() async {
    final map = await _invokeMap('requestIdentityVerification');
    if (map == null) return null;
    final proof = GameCenterIdentityProof.fromMap(map);
    return proof.hasSignatureMaterial ? proof : null;
  }

  Future<List<PlatformPlayer>> _loadPlayers(String method) async {
    final values = await _invoke<List<Object?>?>(method) ?? const <Object?>[];
    return values
        .whereType<Map<Object?, Object?>>()
        .map(PlatformPlayer.fromMap)
        .where((player) => player.playerId.isNotEmpty)
        .toList(growable: false);
  }

  Future<bool> _invokeBool(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    return await _invoke<bool?>(method, arguments) ?? false;
  }

  Future<Map<Object?, Object?>?> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) {
    return _invoke<Map<Object?, Object?>?>(method, arguments);
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final value = await _channel.invokeMethod<T>(method, arguments);
      lastError.value = null;
      return value;
    } on MissingPluginException {
      const exception = PlatformGameServicesException(
        'unsupported_platform',
        'Platform game services are unavailable on this device.',
      );
      lastError.value = exception.toString();
      throw exception;
    } on PlatformException catch (error) {
      final exception = PlatformGameServicesException(
        error.code,
        error.message ?? 'Platform game services request failed.',
      );
      lastError.value = exception.toString();
      throw exception;
    } catch (error) {
      lastError.value = 'unexpected_error: $error';
      rethrow;
    }
  }
}

int _intFromMap(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
