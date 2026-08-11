import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class FirebaseRuntimeConfig {
  const FirebaseRuntimeConfig._();

  static const String expectedProjectId = 'focus-sweep-503417-d7';

  static bool get configured {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return DefaultFirebaseOptions.android.projectId == expectedProjectId;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return DefaultFirebaseOptions.ios.projectId == expectedProjectId;
    }
    return false;
  }

  static FirebaseOptions get options {
    if (!configured) {
      throw StateError('Firebase runtime configuration is incomplete.');
    }

    final options = DefaultFirebaseOptions.currentPlatform;
    if (options.projectId != expectedProjectId) {
      throw StateError(
        'Firebase configuration belongs to ${options.projectId}, '
        'expected $expectedProjectId.',
      );
    }
    return options;
  }

  static Future<bool> initializeIfConfigured() async {
    if (!configured) return false;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    } else {
      final activeProject = Firebase.app().options.projectId;
      if (activeProject != expectedProjectId) {
        throw StateError(
          'The active Firebase app belongs to $activeProject, '
          'expected $expectedProjectId.',
        );
      }
    }
    return true;
  }
}
