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
  await ReminderNotificationService.instance.initialize();
  await PushNotificationService.instance.initialize();
  runApp(SudokuApp(store: store, strings: strings));
  unawaited(AdsService.instance.initialize());
}
