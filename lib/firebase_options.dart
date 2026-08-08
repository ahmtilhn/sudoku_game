// File generated from Firebase app configuration for focus-sweep-503417-d7.
// Re-run FlutterFire CLI when Firebase apps or enabled products change.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase options are configured only for Android and iOS.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase options are configured only for Android and iOS.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDB5B9tqMae8LVB9Ct-x9_HhPrZAZnBXFY',
    appId: '1:31445697560:android:ed951eabf51d75800b2f6d',
    messagingSenderId: '31445697560',
    projectId: 'focus-sweep-503417-d7',
    storageBucket: 'focus-sweep-503417-d7.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCBhzcaJRs1KrbwPQOeBfg657RW8XZmrI0',
    appId: '1:31445697560:ios:44db104825e7d34e0b2f6d',
    messagingSenderId: '31445697560',
    projectId: 'focus-sweep-503417-d7',
    storageBucket: 'focus-sweep-503417-d7.firebasestorage.app',
    iosClientId:
        '31445697560-7pllolpll0e6eccr7eudk32mhg7e88nh.apps.googleusercontent.com',
    iosBundleId: 'com.devovia.sudokuduel',
  );
}
