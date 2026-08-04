import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

  test('Play Games project ID is a numeric non-placeholder value', () {
    final services = File(
      'android/app/src/main/res/values/services.xml',
    ).readAsStringSync();
    final match = RegExp(
      r'<string name="game_services_project_id"[^>]*>(\d+)</string>',
    ).firstMatch(services);

    expect(match, isNotNull);
    final projectId = match!.group(1)!;
    expect(projectId, isNot('0000000000'));
    expect(projectId.length, inInclusiveRange(10, 20));
  });
}
