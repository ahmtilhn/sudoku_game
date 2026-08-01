import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_runtime_config.dart';

class FirebaseSessionException implements Exception {
  const FirebaseSessionException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class FirebaseSessionService {
  const FirebaseSessionService._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static User? get currentUser =>
      Firebase.apps.isEmpty ? null : _auth.currentUser;

  static bool get isAnonymous => currentUser?.isAnonymous ?? true;

  static bool get isProtected {
    final user = currentUser;
    return user != null && !user.isAnonymous;
  }

  static Future<User> ensureAnonymousSession() async {
    final configured = await FirebaseRuntimeConfig.initializeIfConfigured();
    if (!configured) {
      throw const FirebaseSessionException(
        'Firebase is not configured for this device.',
        code: 'firebase_not_configured',
      );
    }

    final existing = _auth.currentUser;
    if (existing != null) return existing;

    try {
      final credential = await _auth.signInAnonymously().timeout(
        const Duration(seconds: 15),
      );
      final user = credential.user ?? _auth.currentUser;
      if (user == null) {
        throw const FirebaseSessionException(
          'Unable to create a temporary player session.',
          code: 'guest_session_failed',
        );
      }
      return user;
    } on TimeoutException {
      throw const FirebaseSessionException(
        'Player session creation timed out. Please try again.',
        code: 'session_timeout',
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  static Future<User> protectCurrentAccount({
    required String email,
    required String password,
  }) async {
    await ensureAnonymousSession();
    final user = _auth.currentUser;
    if (user == null) {
      throw const FirebaseSessionException(
        'No player session is available.',
        code: 'session_missing',
      );
    }
    if (!user.isAnonymous) return user;

    final normalizedEmail = _normalizeEmail(email);
    _validatePassword(password);
    try {
      final credential = EmailAuthProvider.credential(
        email: normalizedEmail,
        password: password,
      );
      final result = await user
          .linkWithCredential(credential)
          .timeout(const Duration(seconds: 20));
      final linked = result.user ?? _auth.currentUser;
      if (linked == null) {
        throw const FirebaseSessionException(
          'The player account could not be protected.',
          code: 'account_link_failed',
        );
      }
      if (!linked.emailVerified) {
        await linked.sendEmailVerification();
      }
      await linked.getIdToken(true);
      return linked;
    } on TimeoutException {
      throw const FirebaseSessionException(
        'Account protection timed out. Please try again.',
        code: 'account_link_timeout',
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  static Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final configured = await FirebaseRuntimeConfig.initializeIfConfigured();
    if (!configured) {
      throw const FirebaseSessionException(
        'Firebase is not configured for this device.',
        code: 'firebase_not_configured',
      );
    }
    final normalizedEmail = _normalizeEmail(email);
    _validatePassword(password);
    try {
      final result = await _auth
          .signInWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          )
          .timeout(const Duration(seconds: 20));
      final user = result.user;
      if (user == null) {
        throw const FirebaseSessionException(
          'The protected account could not be opened.',
          code: 'sign_in_failed',
        );
      }
      await user.getIdToken(true);
      return user;
    } on TimeoutException {
      throw const FirebaseSessionException(
        'Sign-in timed out. Please try again.',
        code: 'sign_in_timeout',
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  static Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous || user.emailVerified) return;
    try {
      await user.sendEmailVerification().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const FirebaseSessionException(
        'Verification email request timed out.',
        code: 'verification_timeout',
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  static Future<void> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.reload().timeout(const Duration(seconds: 15));
      await _auth.currentUser?.getIdToken(true);
    } on TimeoutException {
      throw const FirebaseSessionException(
        'Account refresh timed out.',
        code: 'account_refresh_timeout',
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  static Future<void> sendPasswordReset(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    try {
      await _auth
          .sendPasswordResetEmail(email: normalizedEmail)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const FirebaseSessionException(
        'Password reset request timed out.',
        code: 'password_reset_timeout',
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  static Future<User> signOutToGuest() async {
    try {
      await _auth.signOut();
      return ensureAnonymousSession();
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  static String _normalizeEmail(String value) {
    final email = value.trim().toLowerCase();
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    if (!valid || email.length > 254) {
      throw const FirebaseSessionException(
        'Enter a valid email address.',
        code: 'invalid_email',
      );
    }
    return email;
  }

  static void _validatePassword(String value) {
    if (value.length < 8) {
      throw const FirebaseSessionException(
        'Use a password with at least 8 characters.',
        code: 'weak_password',
      );
    }
    if (value.length > 128) {
      throw const FirebaseSessionException(
        'The password is too long.',
        code: 'invalid_password',
      );
    }
  }

  static FirebaseSessionException _mapAuthError(FirebaseAuthException error) {
    final message = switch (error.code) {
      'email-already-in-use' || 'credential-already-in-use' =>
        'This email already belongs to a protected Sudoku Duel account. Use Sign in instead.',
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' => 'Use a stronger password with at least 8 characters.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'The email or password is incorrect.',
      'too-many-requests' =>
        'Too many attempts were made. Wait a moment and try again.',
      'network-request-failed' =>
        'The account service could not be reached. Check your connection.',
      'operation-not-allowed' =>
        'Email account protection is not enabled for this app yet.',
      'requires-recent-login' => 'Sign in again before changing this account.',
      _ => error.message ?? 'The player account request failed.',
    };
    return FirebaseSessionException(message, code: error.code);
  }
}
