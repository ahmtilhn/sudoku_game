import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  Future<bool> showPlayerProfile(String playerId) => _invokeBool(
        'showPlayerProfile',
        <String, Object>{'playerId': playerId},
      );

  Future<bool> showAchievements() => _invokeBool('showAchievements');

  Future<bool> showLeaderboard({String? leaderboardId}) => _invokeBool(
        'showLeaderboard',
        <String, Object?>{'leaderboardId': leaderboardId},
      );

  Future<bool> submitScore({
    required int score,
    String? leaderboardId,
  }) =>
      _invokeBool(
        'submitScore',
        <String, Object?>{
          'leaderboardId': leaderboardId,
          'score': score,
        },
      );

  Future<bool> unlockAchievement({String? achievementId}) => _invokeBool(
        'unlockAchievement',
        <String, Object?>{'achievementId': achievementId},
      );

  Future<String?> requestServerAuthCode() async {
    final value = await _invoke<Object?>('requestServerAuthCode');
    return value?.toString();
  }

  Future<Map<Object?, Object?>?> requestIdentityVerification() =>
      _invokeMap('requestIdentityVerification');

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
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const PlatformGameServicesException(
        'unsupported_platform',
        'Platform game services are unavailable on this device.',
      );
    } on PlatformException catch (error) {
      throw PlatformGameServicesException(
        error.code,
        error.message ?? 'Platform game services request failed.',
      );
    }
  }
}
