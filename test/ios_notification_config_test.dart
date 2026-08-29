import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS runner is provisioned for APNs in every build mode', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(entitlements, contains('<key>aps-environment</key>'));
    expect(entitlements, contains('<string>\$(APS_ENVIRONMENT)</string>'));
    expect(project, contains('APS_ENVIRONMENT = development;'));
    expect(project, contains('APS_ENVIRONMENT = production;'));
    expect(project, contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'));
  });

  test('Firebase iOS configuration matches the shipping bundle identifier', () {
    final firebase = File(
      'ios/Runner/GoogleService-Info.plist',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(firebase, contains('<string>com.devovia.sudokuduel</string>'));
    expect(firebase, contains('<string>focus-sweep-503417-d7</string>'));
    expect(firebase, contains('<key>IS_GCM_ENABLED</key>'));
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = com.devovia.sudokuduel;'));
  });

  test('iOS notification localization catalog is bundled with Runner', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final catalog = File(
      'assets/localization/Localizable.xcstrings',
    ).readAsStringSync();

    expect(project, contains('Localizable.xcstrings in Resources'));
    expect(project, contains('../../assets/localization/Localizable.xcstrings'));
    expect(catalog, contains('"push_challenge_title"'));
    expect(catalog, contains('"push_rematch_title"'));
    expect(catalog, contains('"push_friend_request_title"'));
  });

  test('Firebase delegate proxy remains enabled for APNs token forwarding', () {
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    // firebase_messaging relies on Firebase AppDelegate swizzling unless the
    // app manually forwards APNs callbacks. This project intentionally uses
    // the default enabled proxy, so a false override must never be introduced.
    expect(
      info,
      isNot(contains('<key>FirebaseAppDelegateProxyEnabled</key>\n\t<false/>')),
    );
  });

  test('push registration waits for an APNs token on iOS', () {
    final push = File(
      'lib/services/push_notification_service.dart',
    ).readAsStringSync();

    expect(push, contains('Platform.isIOS'));
    expect(push, contains('getAPNSToken()'));
    expect(push, contains('FirebaseMessaging.instance.getToken()'));
  });
}
