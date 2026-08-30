import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sudoku_game/data/local_progress_store.dart';
import 'package:sudoku_game/features/settings/ux_settings_screen.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/localization/settings_strings.dart';
import 'package:sudoku_game/services/push_notification_service.dart';
import 'package:sudoku_game/services/social_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localizationChannel = MethodChannel('com.devovia.sudoku/localization');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          localizationChannel,
          (_) async => AppStrings.english,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localizationChannel, null);
  });

  testWidgets('challenge notification switch reflects runtime availability', (
    tester,
  ) async {
    final store = await LocalProgressStore.createInMemory();
    final strings = AppStrings.forTesting();

    await tester.pumpWidget(
      AppStringsScope(
        strings: strings,
        child: MaterialApp(home: UxSettingsScreen(store: store)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(strings.text('notifications')).first);
    await tester.pump();

    final titleText = strings.text('online_challenge_notifications');
    final notificationTitle = find.text(titleText);

    expect(notificationTitle, findsOneWidget);

    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, titleText),
    );
    final available =
        PushNotificationService.instance.configured &&
        SocialApiClient.instance.configured;

    expect(
      find.text(
        strings.text(
          available
              ? 'online_challenge_notifications_subtitle'
              : 'online_challenge_notifications_unavailable',
        ),
      ),
      findsOneWidget,
    );
    expect(tile.onChanged, available ? isNotNull : isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('legacy account protection is removed and data controls remain', (
    tester,
  ) async {
    final store = await LocalProgressStore.createInMemory();
    final strings = AppStrings.forTesting();

    await tester.pumpWidget(
      AppStringsScope(
        strings: strings,
        child: MaterialApp(home: UxSettingsScreen(store: store)),
      ),
    );
    await tester.pump();

    expect(find.text(strings.text('player_account')), findsNothing);
    expect(find.text(strings.text('protect_player_account')), findsNothing);
    expect(find.text(strings.text('coin_history')), findsNothing);

    await tester.tap(find.text(strings.text('data')).first);
    await tester.pump();

    expect(find.text(strings.text('clear_career_progress')), findsOneWidget);
    expect(find.text(strings.text('delete_player_account')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('privacy section exposes the privacy policy', (tester) async {
    final store = await LocalProgressStore.createInMemory();
    final strings = AppStrings.forTesting();

    await tester.pumpWidget(
      AppStringsScope(
        strings: strings,
        child: MaterialApp(home: UxSettingsScreen(store: store)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(strings.text('privacy')).first);
    await tester.pump();

    final context = tester.element(find.byType(UxSettingsScreen));
    expect(
      find.text(SettingsStrings.privacyPolicyTitle(context)),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
