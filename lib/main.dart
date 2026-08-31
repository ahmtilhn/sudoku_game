import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/local_progress_store.dart';
import 'localization/app_strings.dart';
import 'services/achievement_sync_service.dart';
import 'services/ads_service.dart';
import 'services/career_reward_sync_service.dart';
import 'services/coin_store_service.dart';
import 'services/economy_service.dart';
import 'services/economy_v3_service.dart';
import 'services/firebase_services.dart';
import 'services/haptic_feedback_service.dart';
import 'services/play_games_firebase_auth_service.dart';
import 'services/platform_game_services.dart';
import 'services/platform_game_stats_service.dart';
import 'services/platform_leaderboard_service.dart';
import 'services/push_notification_service.dart';
import 'services/reminder_notification_service.dart';
import 'services/sound_effects_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  final store = await LocalProgressStore.create();
  final strings = await AppStrings.load();
  await HapticFeedbackService.instance.initialize();
  await SoundEffectsService.instance.initialize();
  CareerRewardSyncService.instance.bind(store);

  // Firebase and App Check are prerequisites for every authenticated online
  // service. Activate them before the widget tree can start profile, economy,
  // matchmaking, leaderboard, or push requests.
  await _initializeOptionalService(
    'Firebase and App Check bootstrap',
    FirebaseServices.instance.initialize,
    timeout: const Duration(seconds: 30),
  );

  runApp(SudokuApp(store: store, strings: strings));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _initializeOptionalService(
        'daily reminders',
        ReminderNotificationService.instance.initialize,
      ),
    );
    unawaited(
      _initializeOptionalService('Play Games and push', () async {
        // Resolve the permanent Play Games-linked Firebase account before push
        // initialization is allowed to create a guest Firebase session.
        await _initializeOptionalService(
          'Google Play Games',
          _initializeGooglePlayGames,
          timeout: const Duration(seconds: 30),
        );

        final push = PushNotificationService.instance;
        await push.initialize();

        // Startup must never display the OS notification permission prompt.
        // Only an explicit opt-in from Settings may request permission. Existing
        // opted-in users simply refresh their current token when permission is
        // already available.
        if (!push.userDisabled.value && push.permissionGranted.value) {
          await push.refreshRegistration();
        }

        await PlatformLeaderboardService.instance.syncAuthoritativeRatings(
          allowInteractiveAuthentication: false,
        );
      }, timeout: const Duration(seconds: 60)),
    );
    unawaited(
      _initializeOptionalService(
        'ads and consent',
        AdsService.instance.initialize,
        timeout: const Duration(seconds: 60),
      ),
    );
    unawaited(
      _initializeOptionalService('online Coin economy', () async {
        await EconomyService.instance.initialize();
        await EconomyV3Service.instance.initialize();
        await CareerRewardSyncService.instance.syncNow();
      }, timeout: const Duration(seconds: 30)),
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
  // Construct the account bridge before probing authentication. This registers
  // the callback that links Firebase after a later user-initiated Play Games
  // sign-in, even when automatic sign-in did not succeed during startup.
  final accountBridge = PlayGamesFirebaseAuthService.instance;
  if (!await games.isConfigured()) return;

  // Play Games v2 already performs an automatic sign-in attempt. Startup must
  // never call the interactive signIn() API, otherwise the system account panel
  // can repeatedly appear on every launch or route refresh.
  final authenticated = await games.refreshAuthentication();
  if (!authenticated) return;

  // Restore/link the permanent Firebase account using the one-time Play Games
  // server auth code. Failures remain optional and never block offline Sudoku.
  await accountBridge.restoreSilently();

  await PlatformGameStatsService.instance.initialize();
  await PlatformLeaderboardService.instance.syncAuthoritativeRatings(
    allowInteractiveAuthentication: false,
  );
  await AchievementSyncService.instance.syncNow();
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
