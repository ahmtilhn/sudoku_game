import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/local_progress_store.dart';
import 'localization/app_strings.dart';
import 'services/ads_service.dart';
import 'services/coin_store_service.dart';
import 'services/economy_service.dart';
import 'services/firebase_services.dart';
import 'services/platform_game_services.dart';
import 'services/platform_game_stats_service.dart';
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
      _initializeOptionalService('Firebase and push', () async {
        await FirebaseServices.instance.initialize();
        await PushNotificationService.instance.initialize();
      }, timeout: const Duration(seconds: 60)),
    );
    unawaited(
      _initializeOptionalService(
        'Google Play Games',
        _initializeGooglePlayGames,
        timeout: const Duration(seconds: 30),
      ),
    );
    unawaited(
      _initializeOptionalService(
        'ads and consent',
        AdsService.instance.initialize,
        timeout: const Duration(seconds: 60),
      ),
    );
    unawaited(
      _initializeOptionalService(
        'online Coin economy',
        EconomyService.instance.initialize,
        timeout: const Duration(seconds: 30),
      ),
    );
    unawaited(
      _initializeOptionalService(
        'Coin Store',
        CoinStoreService.instance.initialize,
        timeout: const Duration(seconds: 45),
      ),
    );
  });
}

Future<void> _initializeGooglePlayGames() async {
  final games = PlatformGameServices.instance;
  if (!await games.isConfigured()) return;

  var authenticated = await games.refreshAuthentication();
  if (!authenticated) {
    authenticated = await games.authenticate();
  }
  if (!authenticated) return;

  await PlatformGameStatsService.instance.initialize();
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
