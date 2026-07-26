import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/firebase_options.dart';
import 'package:sudoku_game/services/firebase_runtime_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Firebase runtime accepts only the configured project', () {
    expect(FirebaseRuntimeConfig.expectedProjectId, 'focus-sweep-503417-d7');
    expect(
      DefaultFirebaseOptions.android.projectId,
      FirebaseRuntimeConfig.expectedProjectId,
    );
    expect(
      DefaultFirebaseOptions.ios.projectId,
      FirebaseRuntimeConfig.expectedProjectId,
    );
  });

  test('Firebase runtime is enabled for Android and iOS only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(FirebaseRuntimeConfig.configured, isTrue);
    expect(
      FirebaseRuntimeConfig.options.projectId,
      FirebaseRuntimeConfig.expectedProjectId,
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(FirebaseRuntimeConfig.configured, isTrue);
    expect(
      FirebaseRuntimeConfig.options.projectId,
      FirebaseRuntimeConfig.expectedProjectId,
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(FirebaseRuntimeConfig.configured, isFalse);
    expect(() => FirebaseRuntimeConfig.options, throwsStateError);
  });
}
