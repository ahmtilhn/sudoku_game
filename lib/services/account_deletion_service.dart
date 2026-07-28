import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firebase_session_service.dart';
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

    String? appCheck;
    try {
      appCheck = await FirebaseAppCheck.instance
          .getToken()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      appCheck = null;
    }

    final response = await _client
        .post(
          Uri.parse('$baseUrl/v1/me/delete'),
          headers: <String, String>{
            'authorization': 'Bearer $idToken',
            'content-type': 'application/json',
            if (appCheck != null && appCheck.isNotEmpty)
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

    await FirebaseSessionService.ensureAnonymousSession();
  }
}
