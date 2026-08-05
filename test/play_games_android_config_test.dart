import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const expectedPlayGamesProjectId = '917838292556';
const expectedPlayGamesServerClientId =
    '917838292556-bbq7a36t2kulodpqfd9p3aqkkcs58jhj.apps.googleusercontent.com';
const expectedFirebaseProjectId = 'focus-sweep-503417-d7';
const expectedFirebaseProjectNumber = '31445697560';

void main() {
  test('Android manifest uses the Play Games project ID resource', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:name="com.google.android.gms.games.APP_ID"'),
    );
    expect(
      manifest,
      contains('android:value="@string/game_services_project_id"'),
    );
    expect(manifest, isNot(contains('android:value="@string/app_id"')));
  });

  test('Android application initializes Play Games with the same project ID', () {
    final application = File(
      'android/app/src/main/kotlin/com/devoviastudio/sudoku/SudokuApplication.kt',
    ).readAsStringSync();

    expect(application, contains('R.string.game_services_project_id'));
    expect(application, isNot(contains('R.string.app_id')));
  });

  test('Play Games resources use the linked project and game-server client', () {
    final services = File(
      'android/app/src/main/res/values/services.xml',
    ).readAsStringSync();

    expect(
      services,
      contains(
        '<string name="game_services_project_id" translatable="false">'
        '$expectedPlayGamesProjectId</string>',
      ),
    );
    expect(
      services,
      contains(
        '<string name="game_services_web_client_id" translatable="false">'
        '$expectedPlayGamesServerClientId</string>',
      ),
    );
  });

  test('Firebase runtime config remains on the Firebase project', () {
    final raw = File('android/app/google-services.json').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final projectInfo = json['project_info'] as Map<String, dynamic>;

    expect(projectInfo['project_id'], expectedFirebaseProjectId);
    expect(
      projectInfo['project_number'].toString(),
      expectedFirebaseProjectNumber,
    );
    expect(raw, isNot(contains(expectedPlayGamesServerClientId)));
  });

  test('release validation pins the split-project OAuth architecture', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final verifier = File(
      'tool/verify_android_release_config.ps1',
    ).readAsStringSync();

    expect(gradle, contains(expectedPlayGamesProjectId));
    expect(gradle, contains(expectedPlayGamesServerClientId));
    expect(verifier, contains(expectedPlayGamesProjectId));
    expect(verifier, contains(expectedPlayGamesServerClientId));
    expect(
      gradle,
      isNot(
        contains(
          'The Play Games server OAuth client in services.xml is not present '
          'as a web client in google-services.json.',
        ),
      ),
    );
  });
}
