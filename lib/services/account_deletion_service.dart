import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firebase_session_service.dart';
import 'firebase_services.dart';
import 'platform_game_services.dart';
import 'social_api_client.dart';

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class AccountDeletionService {
  AccountDeletionService._();

  static final AccountDeletionService instance = AccountDeletionService._();

  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client = http.Client();

  Future<void> deleteCurrentAccount({String? password}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const AccountDeletionException(
        'No player account is signed in.',
        code: 'account_missing',
      );
    }

    if (!user.isAnonymous) {
      final providerIds = user.providerData
          .map((provider) => provider.providerId)
          .toSet();
      final passwordAccount = providerIds.contains('password');
      final playGamesAccount = providerIds.contains(
        PlayGamesAuthProvider.PROVIDER_ID,
      );

      if (passwordAccount) {
        final email = user.email;
        if (email == null || email.isEmpty || password == null) {
          throw const AccountDeletionException(
            'Enter your password to delete this account.',
            code: 'password_required',
          );
        }
        try {
          await user
              .reauthenticateWithCredential(
                EmailAuthProvider.credential(email: email, password: password),
              )
              .timeout(_timeout);
        } on FirebaseAuthException catch (error) {
          throw AccountDeletionException(
            error.code == 'invalid-credential' || error.code == 'wrong-password'
                ? 'The password is incorrect.'
                : error.message ?? 'Account confirmation failed.',
            code: error.code,
          );
        } on TimeoutException {
          throw const AccountDeletionException(
            'Account confirmation timed out.',
            code: 'reauthentication_timeout',
          );
        }
      } else if (playGamesAccount) {
        await _reauthenticatePlayGames(user);
      } else {
        throw const AccountDeletionException(
          'Reconnect this player account before deleting it.',
          code: 'reauthentication_method_unavailable',
        );
      }
    }

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw const AccountDeletionException(
        'The player token could not be refreshed.',
        code: 'token_missing',
      );
    }
    final baseUrl = SocialApiClient.instance.baseUrl;
    if (baseUrl.isEmpty) {
      throw const AccountDeletionException(
        'The account service is not configured.',
        code: 'backend_not_configured',
      );
    }

    final String appCheck;
    try {
      appCheck = await FirebaseServices.instance.requireAppCheckToken(
        timeout: _timeout,
      );
    } on TimeoutException {
      throw const AccountDeletionException(
        'App Check verification timed out.',
        code: 'app_check_timeout',
      );
    } catch (_) {
      throw const AccountDeletionException(
        'App Check could not verify this installation.',
        code: 'app_check_failed',
      );
    }

    final response = await _client
        .post(
          Uri.parse('$baseUrl/v1/me/delete'),
          headers: <String, String>{
            'authorization': 'Bearer $idToken',
            'content-type': 'application/json',
            'x-firebase-appcheck': appCheck,
          },
          body: '{}',
        )
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'The account could not be deleted.';
      String? code;
      try {
        final body = jsonDecode(response.body);
        if (body is Map) {
          message = body['error']?.toString() ?? message;
          code = body['code']?.toString();
        }
      } catch (_) {
        // Preserve the safe fallback message.
      }
      throw AccountDeletionException(message, code: code);
    }

    try {
      await user.delete().timeout(_timeout);
    } on FirebaseAuthException catch (error) {
      await FirebaseAuth.instance.signOut();
      throw AccountDeletionException(
        'Server data was deleted, but Firebase sign-out needs attention. Restart the app; the deleted player cannot be recreated.',
        code: error.code,
      );
    } on TimeoutException {
      await FirebaseAuth.instance.signOut();
      throw const AccountDeletionException(
        'Server data was deleted. Firebase deletion timed out; restart the app to finish signing out.',
        code: 'firebase_delete_timeout',
      );
    }

    // Do not immediately re-link the platform account that the player just
    // deleted. Continue with a fresh guest session for the current install.
    await FirebaseSessionService.ensureAnonymousSession(restorePlayGames: false);
  }

  Future<void> _reauthenticatePlayGames(User user) async {
    final games = PlatformGameServices.instance;
    try {
      final configured = await games.isConfigured().timeout(_timeout);
      if (!configured) {
        throw const AccountDeletionException(
          'Google Play Games must be available before deleting this player account.',
          code: 'play_games_not_configured',
        );
      }

      var authenticated = await games.refreshAuthentication().timeout(_timeout);
      if (!authenticated) {
        authenticated = await games
            .authenticate(notifyAccountBridge: false)
            .timeout(_timeout);
      }
      if (!authenticated) {
        throw const AccountDeletionException(
          'Reconnect Google Play Games before deleting this player account.',
          code: 'play_games_not_authenticated',
        );
      }

      final code = await games.requestServerAuthCode().timeout(_timeout);
      if (code == null || code.trim().isEmpty) {
        throw const AccountDeletionException(
          'Google Play Games could not confirm this player account.',
          code: 'play_games_auth_code_missing',
        );
      }

      await user
          .reauthenticateWithCredential(
            PlayGamesAuthProvider.credential(serverAuthCode: code.trim()),
          )
          .timeout(_timeout);
      await user.getIdToken(true).timeout(_timeout);
    } on AccountDeletionException {
      rethrow;
    } on PlatformGameServicesException catch (error) {
      throw AccountDeletionException(
        'Reconnect Google Play Games before deleting this player account.',
        code: error.code,
      );
    } on FirebaseAuthException catch (error) {
      throw AccountDeletionException(
        error.message ?? 'Google Play Games account confirmation failed.',
        code: error.code,
      );
    } on TimeoutException {
      throw const AccountDeletionException(
        'Google Play Games account confirmation timed out.',
        code: 'play_games_reauthentication_timeout',
      );
    }
  }
}
