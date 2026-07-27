import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_runtime_config.dart';

class FirebaseSessionException implements Exception {
  const FirebaseSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseSessionService {
  const FirebaseSessionService._();

  static Future<User> ensureAnonymousSession() async {
    final configured = await FirebaseRuntimeConfig.initializeIfConfigured();
    if (!configured) {
      throw const FirebaseSessionException(
        'Firebase is not configured for this device.',
      );
    }

    final existing = FirebaseAuth.instance.currentUser;
    if (existing != null) return existing;

    try {
      final credential = await FirebaseAuth.instance
          .signInAnonymously()
          .timeout(const Duration(seconds: 15));
      final user = credential.user ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw const FirebaseSessionException(
          'Unable to create a temporary player session.',
        );
      }
      return user;
    } on TimeoutException {
      throw const FirebaseSessionException(
        'Player session creation timed out. Please try again.',
      );
    } on FirebaseAuthException catch (error) {
      throw FirebaseSessionException(
        error.message ?? 'Unable to create a temporary player session.',
      );
    }
  }
}
