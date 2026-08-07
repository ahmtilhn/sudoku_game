import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sudoku_game/app.dart';
import 'package:sudoku_game/data/local_progress_store.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/widgets/duel_asset_icon.dart';
import 'package:sudoku_game/widgets/player_avatar.dart';

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

  testWidgets('home exposes a compact asset hierarchy without a tab shell', (
    tester,
  ) async {
    final store = await LocalProgressStore.createInMemory();
    final strings = AppStrings.forTesting();

    await tester.pumpWidget(SudokuApp(store: store, strings: strings));
    await tester.pump();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Career'), findsOneWidget);
    expect(find.text('Online Duel'), findsOneWidget);
    expect(find.text('Friends & challenges'), findsWidgets);
    expect(find.text('Coin Store'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Daily Sudoku'), findsNothing);
    expect(find.text('Ranked'), findsNothing);
    expect(find.text('Practice'), findsNothing);
    expect(find.text('Protect your player account'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is NavigationBar || widget is NavigationRail,
      ),
      findsNothing,
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(PlayerAvatar), findsWidgets);
    expect(find.byType(DuelAssetIcon), findsAtLeastNWidgets(8));
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byIcon(Icons.people_alt_rounded), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
