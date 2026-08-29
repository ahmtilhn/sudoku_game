import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Owns the single native local-notification plugin instance for the app.
///
/// Push and scheduled reminders both use this bridge so one service cannot
/// overwrite the notification-tap callback registered by the other.
class NotificationPlatformService {
  NotificationPlatformService._();

  static final NotificationPlatformService instance =
      NotificationPlatformService._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<String?> openedPayload = ValueNotifier<String?>(null);

  Future<void>? _initialization;
  bool _initialized = false;

  bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() {
    if (_initialized || !supported) return Future<void>.value();
    return _initialization ??= _initializeOnce().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initializeOnce() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        _publishOpenedPayload(response.payload);
      },
    );

    _initialized = true;

    // onDidReceiveNotificationResponse is not invoked when a local
    // notification launches a terminated app. Recover that payload explicitly.
    final launchDetails = await plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _publishOpenedPayload(launchDetails?.notificationResponse?.payload);
    }
  }

  Future<bool> systemPermissionGranted() async {
    if (!supported) return false;
    await initialize();

    if (Platform.isAndroid) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }

    final options = await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  void consumePayload(String payload) {
    if (openedPayload.value == payload) openedPayload.value = null;
  }

  void _publishOpenedPayload(String? payload) {
    final normalized = payload?.trim();
    if (normalized == null || normalized.isEmpty) return;
    openedPayload.value = normalized;
  }
}
