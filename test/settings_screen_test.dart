import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sudoku_game/data/local_progress_store.dart';
import 'package:sudoku_game/features/settings/settings_screen.dart';
import 'package:sudoku_game/localization/app_strings.dart';

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

  testWidgets(
    'challenge notification switch is disabled when backend is unavailable',
    (tester) async {
      final store = await LocalProgressStore.createInMemory();
      final strings = await AppStrings.load();

      await tester.pumpWidget(
        AppStringsScope(
          strings: strings,
          child: MaterialApp(home: SettingsScreen(store: store)),
        ),
      );
      await tester.pump();

      expect(find.text('Online challenge notifications'), findsOneWidget);
      expect(
        find.text(
          'Challenge notifications require Firebase and the social backend to be configured.',
        ),
        findsOneWidget,
      );

      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Online challenge notifications'),
      );
      expect(tile.onChanged, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
