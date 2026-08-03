import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local notifications resolve a drawable icon', () {
    final service = File(
      'lib/services/push_notification_service.dart',
    ).readAsStringSync();
    final aliases = File(
      'android/app/src/main/res/values/notification_icons.xml',
    ).readAsStringSync();
    final icon = File(
      'android/app/src/main/res/drawable/ic_stat_sudoku.xml',
    );

    expect(
      service,
      contains("AndroidInitializationSettings('ic_launcher')"),
    );
    expect(
      aliases,
      contains('<item name="ic_launcher" type="drawable">'),
    );
    expect(aliases, contains('@drawable/ic_stat_sudoku'));
    expect(icon.existsSync(), isTrue);
  });

  test('Firebase background notifications use the Sudoku status icon', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains(
        'android:name="com.google.firebase.messaging.default_notification_icon"',
      ),
    );
    expect(
      manifest,
      contains('android:resource="@drawable/ic_stat_sudoku"'),
    );
  });
}
