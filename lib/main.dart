import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local_progress_store.dart';
import 'localization/app_strings.dart';
import 'services/ads_service.dart';
import 'services/push_notification_service.dart';
import 'services/reminder_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalProgressStore.create();
  final strings = await AppStrings.load();

  runApp(SudokuApp(store: store, strings: strings));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _initializeOptionalService(
        'daily reminders',
        ReminderNotificationService.instance.initialize,
      ),
    );
    unawaited(
      _initializeOptionalService(
        'push notifications',
        PushNotificationService.instance.initialize,
      ),
    );
    unawaited(
      _initializeOptionalService(
        'ads and consent',
        AdsService.instance.initialize,
        timeout: const Duration(seconds: 60),
      ),
    );
  });
}

Future<void> _initializeOptionalService(
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
