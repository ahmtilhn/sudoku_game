import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_runtime_config.dart';
import 'platform_game_services.dart';

class PlayGamesFirebaseAuthException implements Exception {
  const PlayGamesFirebaseAuthException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Binds the Play Games player to Firebase Authentication.
///
/// Linking preserves the current anonymous Firebase UID on first connection, so
/// the nickname and backend profile already created for that UID remain intact.
/// After reinstall, signing in with the same Play Games credential restores the
/// same Firebase UID and therefore the same server-side player account.
class PlayGamesFirebaseAuthService {
  PlayGamesFirebaseAuthService._();

  static final PlayGamesFirebaseAuthService instance =
      PlayGamesFirebaseAuthService._();

  static const Duration _timeout = Duration(seconds: 20);

  Future<User?>? _inFlight;
  DateTime? _lastSilentFailureAt;
  Object? _lastSilentFailure;

  Object? get lastSilentFailure => _lastSilentFailure;

  Future<User?> restoreSilently() {
    final current = Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;
    if (_isPlayGamesUser(current)) return Future<User?>.value(current);

    final lastFailure = _lastSilentFailureAt;
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < const Duration(seconds: 20)) {
      return Future<User?>.value(null);
    }

    final pending = _inFlight;
    if (pending != null) return pending;

    final operation = _authenticate(prompt: false)
        .then<User?>((user) {
          _lastSilentFailureAt = null;
          _lastSilentFailure = null;
          return user;
        })
        .catchError((Object error) {
          _lastSilentFailureAt = DateTime.now();
          _lastSilentFailure = error;
          return null;
        })
        .whenComplete(() => _inFlight = null);
    _inFlight = operation;
    return operation;
  }

  Future<User> connect() async {
    final pending = _inFlight;
    if (pending != null) {
      final existing = await pending;
      if (existing != null) return existing;
    }

    try {
      final user = await _authenticate(prompt: true);
      if (user == null) {
        throw const PlayGamesFirebaseAuthException(
          'Google Play Games authentication was cancelled or did not complete.',
          code: 'play_games_not_authenticated',
        );
      }
      _lastSilentFailureAt = null;
      _lastSilentFailure = null;
      return user;
    } on PlayGamesFirebaseAuthException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw _mapFirebaseError(error);
    } on PlatformGameServicesException catch (error) {
      throw PlayGamesFirebaseAuthException(error.message, code: error.code);
    } on TimeoutException {
      throw const PlayGamesFirebaseAuthException(
        'Google Play Games account connection timed out.',
        code: 'play_games_timeout',
      );
    } catch (error) {
      throw PlayGamesFirebaseAuthException(
        'Google Play Games account connection failed: $error',
        code: 'play_games_connection_failed',
      );
    }
  }

  Future<User?> _authenticate({required bool prompt}) async {
    final configured = await FirebaseRuntimeConfig.initializeIfConfigured();
    if (!configured) {
      if (!prompt) return null;
      throw const PlayGamesFirebaseAuthException(
        'Firebase is not configured for this device.',
        code: 'firebase_not_configured',
      );
    }

    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    if (_isPlayGamesUser(current)) {
      await current!.getIdToken(true).timeout(_timeout);
      return current;
    }

    // Do not silently replace a protected email or another permanent account.
    if (!prompt && current != null && !current.isAnonymous) return current;

    final games = PlatformGameServices.instance;
    final gamesConfigured = await games.isConfigured().timeout(_timeout);
    if (!gamesConfigured) {
      if (!prompt) return null;
      throw const PlayGamesFirebaseAuthException(
        'Google Play Games is not configured for this app.',
        code: 'play_games_not_configured',
      );
    }

    var authenticated = await games.refreshAuthentication().timeout(_timeout);
    if (!authenticated && prompt) {
      authenticated = await games.authenticate().timeout(_timeout);
    }
    if (!authenticated) return null;

    final credential = await _freshCredential(games);
    UserCredential result;

    if (current != null) {
      try {
        result = await current.linkWithCredential(credential).timeout(_timeout);
      } on FirebaseAuthException catch (error) {
        if (error.code == 'provider-already-linked') {
          await current.getIdToken(true).timeout(_timeout);
          return current;
        }
        if (!_credentialBelongsToExistingAccount(error.code)) rethrow;

        // A server auth code is single-use. Request a fresh code before
        // switching to the Firebase account previously linked to this player.
        result = await auth
            .signInWithCredential(await _freshCredential(games))
            .timeout(_timeout);
      }
    } else {
      result = await auth.signInWithCredential(credential).timeout(_timeout);
    }

    final user = result.user ?? auth.currentUser;
    if (user == null) {
      throw const PlayGamesFirebaseAuthException(
        'Firebase did not return a player account after Play Games sign-in.',
        code: 'firebase_play_games_user_missing',
      );
    }
    await user.getIdToken(true).timeout(_timeout);
    return user;
  }

  Future<OAuthCredential> _freshCredential(
    PlatformGameServices games,
  ) async {
    final code = await games.requestServerAuthCode().timeout(_timeout);
    if (code == null || code.trim().isEmpty) {
      throw const PlayGamesFirebaseAuthException(
        'Google Play Games did not return a server authentication code.',
        code: 'server_auth_code_missing',
      );
    }
    return PlayGamesAuthProvider.credential(serverAuthCode: code.trim());
  }

  bool _isPlayGamesUser(User? user) {
    if (user == null || user.isAnonymous) return false;
    return user.providerData.any(
      (provider) => provider.providerId == PlayGamesAuthProvider.PROVIDER_ID,
    );
  }

  bool _credentialBelongsToExistingAccount(String code) {
    return code == 'credential-already-in-use' ||
        code == 'account-exists-with-different-credential';
  }

  PlayGamesFirebaseAuthException _mapFirebaseError(
    FirebaseAuthException error,
  ) {
    final message = switch (error.code) {
      'operation-not-allowed' =>
        'Enable the Play Games sign-in provider in Firebase Authentication.',
      'invalid-credential' =>
        'The Play Games server OAuth credential is invalid or belongs to the wrong project.',
      'user-disabled' => 'This player account has been disabled.',
      'network-request-failed' =>
        'The account service could not be reached. Check your connection.',
      'too-many-requests' =>
        'Too many account requests were made. Wait a moment and try again.',
      _ => error.message ?? 'Firebase Play Games authentication failed.',
    };
    return PlayGamesFirebaseAuthException(message, code: error.code);
  }
}
