import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_message_catalog.dart';

class ReminderNotificationService {
  ReminderNotificationService._();

  static final ReminderNotificationService instance =
      ReminderNotificationService._();

  static const String _enabledKey = 'daily_reminders_enabled_v1';
  static const String _seedKey = 'daily_reminders_seed_v1';
  static const int _firstNotificationId = 10000;
  static const int _notificationCount = 63;
  static const String _payload = 'daily-reminder';

  static const List<({int hour, int minute})> _dailyTimes =
      <({int hour, int minute})>[
        (hour: 9, minute: 0),
        (hour: 15, minute: 0),
        (hour: 20, minute: 30),
      ];

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<String?> openedPayload = ValueNotifier<String?>(null);

  bool _initialized = false;
  int _seed = 1;

  bool get _supportsScheduling =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    enabled.value = await _preferences.getBool(_enabledKey) ?? false;
    _seed =
        await _preferences.getInt(_seedKey) ??
        DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    await _preferences.setInt(_seedKey, _seed);

    if (!_supportsScheduling) {
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

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        openedPayload.value = response.payload;
      },
    );
    _initialized = true;

    if (enabled.value) {
      await refreshSchedule();
    }
  }

  Future<bool> requestPermissionAndEnable() async {
    if (!_initialized) await initialize();
    if (!_supportsScheduling) return false;

    var granted = true;
    if (Platform.isAndroid) {
      granted =
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    } else if (Platform.isIOS) {
      granted =
          await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: false, sound: true) ??
          false;
    }

    if (!granted) return false;

    enabled.value = true;
    await _preferences.setBool(_enabledKey, true);
    await refreshSchedule();
    return true;
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
    final messages = ReminderMessageCatalog.shuffled(seed: _seed ^ daySeed);
    final scheduledDates = _nextScheduleDates(now);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_sudoku_challenges',
        'Daily Sudoku challenges',
        channelDescription:
            'Optional reminders to return for a fresh Sudoku challenge.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(
        threadIdentifier: 'daily-sudoku-challenges',
      ),
    );

    for (var index = 0; index < scheduledDates.length; index++) {
      await _plugin.zonedSchedule(
        id: _firstNotificationId + index,
        title: 'Sudoku Duel',
        body: messages[index],
        scheduledDate: scheduledDates[index],
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: _payload,
      );
    }
  }

  List<tz.TZDateTime> _nextScheduleDates(tz.TZDateTime now) {
    final dates = <tz.TZDateTime>[];
    var dayOffset = 0;
    while (dates.length < _notificationCount) {
      final day = now.add(Duration(days: dayOffset));
      for (final time in _dailyTimes) {
        final candidate = tz.TZDateTime(
          tz.local,
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        );
        if (candidate.isAfter(now.add(const Duration(minutes: 1)))) {
          dates.add(candidate);
          if (dates.length == _notificationCount) break;
        }
      }
      dayOffset++;
    }
    return dates;
  }

  Future<void> _cancelReminderSchedule() async {
    for (var index = 0; index < _notificationCount; index++) {
      await _plugin.cancel(id: _firstNotificationId + index);
    }
  }
}
