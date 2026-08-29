import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/push_notification_service.dart';

void main() {
  group('push destination parsing', () {
    test('accepted challenge opens the ready room', () {
      final destination = parsePushNotificationDestination(<String, dynamic>{
        'type': 'challenge_response',
        'status': 'accepted',
        'challengeId': 'challenge-1',
        'roomId': 'room-1',
      });

      expect(destination, isNotNull);
      expect(destination!.type, PushNotificationDestinationType.room);
      expect(destination.id, 'room-1');
    });

    test('friend and rematch pushes keep their dedicated destinations', () {
      final friend = parsePushNotificationDestination(<String, dynamic>{
        'type': 'friend_request',
        'requesterPublicId': 'FRIEND123',
      });
      final rematch = parsePushNotificationDestination(<String, dynamic>{
        'type': 'rematch_invitation',
        'rematchId': 'rematch-1',
      });

      expect(friend?.type, PushNotificationDestinationType.social);
      expect(friend?.id, 'FRIEND123');
      expect(rematch?.type, PushNotificationDestinationType.rematch);
      expect(rematch?.id, 'rematch-1');
    });

    test('declined challenge is informational and does not navigate', () {
      final destination = parsePushNotificationDestination(<String, dynamic>{
        'type': 'challenge_response',
        'status': 'declined',
        'challengeId': 'challenge-1',
        'roomId': '',
      });

      expect(destination?.type, PushNotificationDestinationType.informational);
      expect(destination?.id, 'challenge-1');
    });
  });

  test('startup never asks notification permission automatically', () {
    final main = File('lib/main.dart').readAsStringSync();

    expect(main, isNot(contains('await push.requestPermissionAndRegister()')));
  });

  test('foreground push receipt does not become an automatic open', () {
    final service = File(
      'lib/services/push_notification_service.dart',
    ).readAsStringSync();
    final start = service.indexOf('Future<void> _handleForegroundMessage');
    final end = service.indexOf(
      'Future<void> _showForegroundSystemNotification',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final handler = service.substring(start, end);
    expect(handler, isNot(contains('_openTarget(')));
    expect(handler, contains('_showForegroundSystemNotification(target)'));
  });

  test('daily reminders persist opt-in and use three recurring schedules', () {
    final service = File(
      'lib/services/reminder_notification_service.dart',
    ).readAsStringSync();

    expect(service, contains('daily_reminders_enabled_v2'));
    expect(service, contains('matchDateTimeComponents: DateTimeComponents.time'));
    expect(service, contains('_dailyTimes.length'));
    expect(service, contains('_legacyNotificationCount = 63'));
    expect(service, contains('await _preferences.setBool(_enabledKey, false)'));
  });

  test('one local-notification plugin owns tap and cold-start callbacks', () {
    final platform = File(
      'lib/services/notification_platform_service.dart',
    ).readAsStringSync();
    final push = File(
      'lib/services/push_notification_service.dart',
    ).readAsStringSync();
    final reminder = File(
      'lib/services/reminder_notification_service.dart',
    ).readAsStringSync();

    expect(platform, contains('FlutterLocalNotificationsPlugin plugin'));
    expect(platform, contains('getNotificationAppLaunchDetails()'));
    expect(push, contains('NotificationPlatformService.instance'));
    expect(reminder, contains('NotificationPlatformService.instance'));
    expect(
      push,
      isNot(contains('FlutterLocalNotificationsPlugin _localNotifications')),
    );
    expect(reminder, isNot(contains('FlutterLocalNotificationsPlugin _plugin')));
  });

  test('backend expires stale invitations and never forces badge one', () {
    final sender = File(
      'backend/social_worker/src/push_notifications.ts',
    ).readAsStringSync();
    final challenges = File(
      'backend/social_worker/src/variant_challenges.ts',
    ).readAsStringSync();

    expect(sender, contains("ttl: `\${ttlSeconds}s`"));
    expect(sender, contains("'apns-expiration'"));
    expect(sender, isNot(contains('badge: 1')));
    expect(
      challenges,
      contains("FCM_PROJECT_ID: 'REPLACE_NOTIFICATION_WRAPPER'"),
    );
    expect(challenges, contains('sendPlayerPush('));
  });

  test('Android native push translations are generated from shared catalog', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('generatePushNotificationLocalizations'));
    expect(gradle, contains('startsWith("push_")'));
    expect(gradle, contains('Localizable.xcstrings'));
    expect(
      gradle,
      contains('dependsOn(generatePushNotificationLocalizations)'),
    );
  });
}
