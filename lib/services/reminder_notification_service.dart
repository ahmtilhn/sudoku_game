import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../localization/app_strings.dart';
import 'notification_platform_service.dart';
import 'reminder_message_catalog.dart';

class ReminderNotificationService {
  ReminderNotificationService._();

  static final ReminderNotificationService instance =
      ReminderNotificationService._();

  static const String _seedKey = 'daily_reminders_seed_v1';
  static const String _enabledKey = 'daily_reminders_enabled_v2';
  static const int _firstNotificationId = 10000;
  static const int _legacyNotificationCount = 63;
  static const String _payload = 'daily-reminder';

  static const List<({int hour, int minute})> _dailyTimes =
      <({int hour, int minute})>[
        (hour: 9, minute: 0),
        (hour: 15, minute: 0),
        (hour: 20, minute: 30),
      ];

  final NotificationPlatformService _platform =
      NotificationPlatformService.instance;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<String?> openedPayload = ValueNotifier<String?>(null);

  bool _initialized = false;
  bool _payloadListenerAttached = false;
  int _seed = 1;
  AppStrings? _strings;

  bool get _supportsScheduling => _platform.supported;

  Future<void> initialize() async {
    if (_initialized) return;

    _strings ??= await AppStrings.load();
    _seed =
        await _preferences.getInt(_seedKey) ??
        DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    await _preferences.setInt(_seedKey, _seed);

    if (!_supportsScheduling) {
      enabled.value = false;
      _initialized = true;
      return;
    }

    tz_data.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    try {
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } on ArgumentError {
      tz.setLocalLocation(tz.getLocation('Etc/UTC'));
    }

    await _platform.initialize();
    if (!_payloadListenerAttached) {
      _platform.openedPayload.addListener(_handlePlatformPayload);
      _payloadListenerAttached = true;
    }
    _handlePlatformPayload();

    _initialized = true;

    // OS permission and the in-app reminder preference are intentionally
    // separate. A permission granted for online pushes must never silently
    // re-enable daily reminders the user switched off.
    final optedIn = await _preferences.getBool(_enabledKey) == true;
    if (!optedIn) {
      enabled.value = false;
      await _cancelReminderSchedule();
      return;
    }

    final granted = await _platform.systemPermissionGranted();
    enabled.value = granted;
    if (granted) {
      await refreshSchedule();
    } else {
      await _cancelReminderSchedule();
    }
  }

  /// Refreshes the switch from the current OS permission without requesting a
  /// permission prompt. Used after returning from system settings/app resume.
  Future<bool> syncWithSystemPermission() async {
    if (!_initialized) await initialize();
    if (!_supportsScheduling) {
      enabled.value = false;
      return false;
    }

    final optedIn = await _preferences.getBool(_enabledKey) == true;
    if (!optedIn) {
      enabled.value = false;
      await _cancelReminderSchedule();
      return false;
    }

    final granted = await _platform.systemPermissionGranted();
    enabled.value = granted;
    if (granted) {
      await refreshSchedule();
    } else {
      await _cancelReminderSchedule();
    }
    return granted;
  }

  Future<bool> requestPermissionAndEnable() async {
    if (!_initialized) await initialize();
    if (!_supportsScheduling) return false;

    final granted = await _requestSystemPermission();
    if (!granted) {
      enabled.value = false;
      return false;
    }

    await _preferences.setBool(_enabledKey, true);
    enabled.value = true;
    await refreshSchedule();
    return true;
  }

  Future<bool> _requestSystemPermission() async {
    await _platform.initialize();
    final plugin = _platform.plugin;
    if (Platform.isAndroid) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false;
    }
    return false;
  }

  Future<void> disable() async {
    enabled.value = false;
    await _preferences.setBool(_enabledKey, false);
    if (_supportsScheduling && _initialized) {
      await _cancelReminderSchedule();
    }
  }

  Future<void> refreshSchedule() async {
    if (!_supportsScheduling || !_initialized || !enabled.value) return;

    await _cancelReminderSchedule();

    final now = tz.TZDateTime.now(tz.local);
    final daySeed = now.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    final strings = _strings ??= await AppStrings.load();
    final messages = ReminderMessageCatalog.shuffled(
      seed: _seed ^ daySeed,
      strings: strings,
    );

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_sudoku_challenges',
        strings.text('daily_sudoku_challenges'),
        channelDescription: strings.text('daily_sudoku_challenges_channel'),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(
        threadIdentifier: 'daily-sudoku-challenges',
      ),
    );

    // Keep exactly three recurring requests instead of reserving 63 one-shot
    // slots. This avoids iOS's pending-notification ceiling and never expires
    // after 21 days when the app has not been reopened.
    for (var index = 0; index < _dailyTimes.length; index++) {
      final time = _dailyTimes[index];
      await _platform.plugin.zonedSchedule(
        id: _firstNotificationId + index,
        title: strings.text('app_name'),
        body: messages[index % messages.length],
        scheduledDate: _nextOccurrence(now, time.hour, time.minute),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: _payload,
      );
    }
  }

  tz.TZDateTime _nextOccurrence(tz.TZDateTime now, int hour, int minute) {
    var candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!candidate.isAfter(now.add(const Duration(minutes: 1)))) {
      candidate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }
    return candidate;
  }

  void _handlePlatformPayload() {
    final payload = _platform.openedPayload.value;
    if (payload != _payload) return;
    openedPayload.value = payload;
    _platform.consumePayload(payload!);
  }

  Future<void> _cancelReminderSchedule() async {
    // Cancel both the old 63 one-shot IDs and the new three repeating IDs so
    // upgrades cannot leave stale reminders behind.
    for (var index = 0; index < _legacyNotificationCount; index++) {
      await _platform.plugin.cancel(id: _firstNotificationId + index);
    }
  }
}
