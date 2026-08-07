import 'dart:convert';
import 'dart:typed_data';

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
    this.avatarBytesBase64,
  });

  final String platform;
  final String playerId;
  final String displayName;
  final String? alias;
  final String? avatarUrl;
  final String? avatarBytesBase64;

  Uint8List? get avatarBytes {
    final value = avatarBytesBase64?.trim();
    if (value == null || value.isEmpty) return null;
    try {
      final bytes = base64Decode(value);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

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
      avatarBytesBase64: map['avatarBytesBase64']?.toString(),
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

@immutable
class PlayGamesDiagnostics {
  const PlayGamesDiagnostics(this.values);

  static const String expectedPlayAppSigningSha1 =
      '53:B0:F0:FF:89:6C:50:AE:B0:86:F2:04:A2:2E:ED:E2:9F:1B:F3:0B';

  final Map<String, String> values;

  factory PlayGamesDiagnostics.fromMap(Map<Object?, Object?> map) {
    return PlayGamesDiagnostics(_stringMap(map));
  }

  String get packageName => values['packageName'] ?? '';
  String get projectId => values['projectId'] ?? '';
  String get certificateSha1 => values['certificateSha1'] ?? '';
  String get installer => values['installer'] ?? '';
  String get version => values['version'] ?? '';
  String get playServicesStatus => values['playServicesStatus'] ?? '';
  String get apiStatusCode => values['apiStatusCode'] ?? '';
  String get apiStatusName => values['apiStatusName'] ?? '';

  bool get installedFromGooglePlay => installer == 'com.android.vending';

  bool get certificateMatchesPlayAppSigning =>
      _normalizeFingerprint(certificateSha1) ==
      _normalizeFingerprint(expectedPlayAppSigningSha1);

  String get conciseSummary {
    final parts = <String>[
      if (packageName.isNotEmpty) 'package=$packageName',
      if (projectId.isNotEmpty) 'playGamesProject=$projectId',
      if (certificateSha1.isNotEmpty) 'sha1=$certificateSha1',
      if (installer.isNotEmpty) 'installer=$installer',
      if (apiStatusCode.isNotEmpty && apiStatusCode != 'none')
        'status=$apiStatusCode ($apiStatusName)',
      if (playServicesStatus.isNotEmpty) 'playServices=$playServicesStatus',
      if (version.isNotEmpty) 'version=$version',
    ];
    return parts.join(', ');
  }
}

class PlatformGameServicesException implements Exception {
  const PlatformGameServicesException(
    this.code,
    this.message, {
    this.diagnostics = const <String, String>{},
  });

  final String code;
  final String message;
  final Map<String, String> diagnostics;

  PlayGamesDiagnostics get playGamesDiagnostics =>
      PlayGamesDiagnostics(diagnostics);

  @override
  String toString() {
    final summary = playGamesDiagnostics.conciseSummary;
    return summary.isEmpty ? '$code: $message' : '$code: $message | $summary';
  }
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

  Future<void> Function()? _afterInteractiveAuthentication;

  void registerAfterInteractiveAuthentication(
    Future<void> Function()? callback,
  ) {
    _afterInteractiveAuthentication = callback;
  }

  Future<bool> isConfigured() => _invokeBool('isConfigured');

  Future<PlayGamesDiagnostics> getDiagnostics() async {
    final map = await _invokeMap('getDiagnostics');
    return PlayGamesDiagnostics.fromMap(map ?? const <Object?, Object?>{});
  }

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

  Future<bool> authenticate({bool notifyAccountBridge = true}) async {
    final value = await _invokeBool('authenticate');
    authenticated.value = value;
    localPlayer.value = value ? await getLocalPlayer() : null;
    if (!value) {
      final diagnostics = await _safeDiagnostics();
      final exception = PlatformGameServicesException(
        'authentication_failed',
        'Google Play Games did not authenticate the current account.',
        diagnostics: diagnostics.values,
      );
      lastError.value = exception.toString();
      return false;
    }

    final callback = notifyAccountBridge
        ? _afterInteractiveAuthentication
        : null;
    if (callback != null) {
      try {
        await callback();
      } catch (error) {
        final diagnostics = await _safeDiagnostics();
        final exception = PlatformGameServicesException(
          'account_link_failed',
          'Google Play Games connected, but the Firebase player account could not be linked: $error',
          diagnostics: diagnostics.values,
        );
        lastError.value = exception.toString();
        throw exception;
      }
    }

    lastError.value = null;
    return true;
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

  Future<bool> recordGameStatsEvents(List<Map<String, Object?>> events) =>
      _invokeBool('recordGameStatsEvents', <String, Object?>{'events': events});

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

  Future<PlayGamesDiagnostics> _safeDiagnostics() async {
    try {
      return await getDiagnostics();
    } catch (_) {
      return const PlayGamesDiagnostics(<String, String>{});
    }
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
        diagnostics: _stringMap(error.details),
      );
      lastError.value = exception.toString();
      throw exception;
    } catch (error) {
      lastError.value = 'unexpected_error: $error';
      rethrow;
    }
  }
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in value.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
}

String _normalizeFingerprint(String value) =>
    value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();

int _intFromMap(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
