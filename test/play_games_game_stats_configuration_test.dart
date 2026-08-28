import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Game Stats uses the required Play Games v22 SDK', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(
      gradle,
      contains(
        'implementation("com.google.android.gms:play-services-games-v2:22.0.0")',
      ),
    );
    expect(
      gradle,
      isNot(contains('play-services-games-v2:21.0.0')),
    );
  });

  test('Android Game Stats resolves the official PlayerGameEvent builder', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/devoviastudio/sudoku/MainActivity.kt',
    ).readAsStringSync();

    expect(
      mainActivity,
      contains(
        r'com.google.android.gms.games.playergameevent.PlayerGameEvent\$Builder',
      ),
    );
    expect(mainActivity, contains('recordGameStatsEvents'));
    expect(mainActivity, contains('getGameStatsClient'));
    expect(mainActivity, contains('requestEventsUpload'));
  });
}
