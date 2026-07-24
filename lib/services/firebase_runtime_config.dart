import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseRuntimeConfig {
  const FirebaseRuntimeConfig._();

  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String androidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const String iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const String iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.devoviastudio.sudoku',
  );

  static bool get configured {
    if (apiKey.isEmpty || projectId.isEmpty || messagingSenderId.isEmpty) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return androidAppId.isNotEmpty;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return iosAppId.isNotEmpty;
    }
    return false;
  }

  static FirebaseOptions get options {
    if (!configured) {
      throw StateError('Firebase runtime configuration is incomplete.');
    }

    final appId = defaultTargetPlatform == TargetPlatform.iOS
        ? iosAppId
        : androidAppId;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
          ? iosBundleId
          : null,
    );
  }
}
