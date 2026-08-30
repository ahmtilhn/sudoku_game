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
  static const String _legacyEnabledKey = 'daily_reminders_enabled_v2';
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

    await syncWithSystemPermission();
  }

  /// Keeps the recurring schedule aligned with the operating-system permission.
  /// There is no in-app daily-reminder opt-out; granting notification permission
  /// enables these reminders automatically.
  Future<bool> syncWithSystemPermission() async {
    if (!_initialized) await initialize();
    if (!_supportsScheduling) {
      enabled.value = false;
      return false;
    }

    await _preferences.remove(_legacyEnabledKey);

    final granted = await _platform.systemPermissionGranted();
    if (!granted) {
      enabled.value = false;
      await _cancelReminderSchedule();
      return false;
    }

    enabled.value = true;
    await refreshSchedule();
    return true;
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
    for (var index = 0; index < _legacyNotificationCount; index++) {
      await _platform.plugin.cancel(id: _firstNotificationId + index);
    }
  }
}
