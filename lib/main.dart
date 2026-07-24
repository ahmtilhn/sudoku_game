import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local_progress_store.dart';
import 'localization/app_strings.dart';
import 'services/ads_service.dart';
import 'services/push_notification_service.dart';
import 'services/reminder_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await _loadProgressStore();
  final strings = await _loadStrings();

  runApp(SudokuApp(store: store, strings: strings));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _startOptionalService(
        'daily reminders',
        ReminderNotificationService.instance.initialize,
      ),
    );
    unawaited(
      _startOptionalService(
        'push notifications',
        PushNotificationService.instance.initialize,
      ),
    );
    unawaited(
      _startOptionalService(
        'ads and consent',
        AdsService.instance.initialize,
        timeout: const Duration(seconds: 60),
      ),
    );
  });
}

Future<LocalProgressStore> _loadProgressStore() async {
  try {
    return await LocalProgressStore.create().timeout(
      const Duration(seconds: 5),
    );
  } catch (error, stackTrace) {
    debugPrint('Progress store startup failed; using an in-memory fallback: $error');
    debugPrintStack(stackTrace: stackTrace);
    return LocalProgressStore.createInMemory();
  }
}

Future<AppStrings> _loadStrings() async {
  try {
    return await AppStrings.load().timeout(const Duration(seconds: 5));
  } catch (error, stackTrace) {
    debugPrint('Localization startup failed; using English fallback: $error');
    debugPrintStack(stackTrace: stackTrace);
    return AppStrings.englishFallback();
  }
}

Future<void> _startOptionalService(
  String name,
  Future<void> Function() initialize, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    await initialize().timeout(timeout);
  } catch (error, stackTrace) {
    debugPrint('Optional startup service "$name" failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
