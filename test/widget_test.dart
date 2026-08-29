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

  testWidgets('home exposes the unified primary UX without a tab shell', (
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
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is DuelAssetIcon && widget.asset == DuelAsset.people,
      ),
      findsWidgets,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('home fits required compact viewports without page scrolling', (
    tester,
  ) async {
    const viewports = <Size>[
      Size(320, 568),
      Size(360, 800),
      Size(412, 915),
      Size(568, 320),
    ];

    for (final viewport in viewports) {
      await tester.binding.setSurfaceSize(viewport);
      final store = await LocalProgressStore.createInMemory();
      final strings = AppStrings.forTesting();

      await tester.pumpWidget(SudokuApp(store: store, strings: strings));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Home overflowed at ${viewport.width}x${viewport.height}',
      );
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Career'), findsOneWidget);
      expect(find.text('Coin Store'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Play opens aligned quick play cards without layout errors', (
    tester,
  ) async {
    final store = await LocalProgressStore.createInMemory();
    final strings = AppStrings.forTesting();

    await tester.pumpWidget(SudokuApp(store: store, strings: strings));
    await tester.pump();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final dialog = find.byKey(const ValueKey<String>('quick-play-dialog'));
    expect(dialog, findsOneWidget);

    final nine = find.descendant(of: dialog, matching: find.text('9×9'));
    final sixteen = find.descendant(of: dialog, matching: find.text('16×16'));
    expect(nine, findsOneWidget);
    expect(sixteen, findsOneWidget);
    expect(
      tester.getCenter(nine).dy,
      moreOrLessEquals(tester.getCenter(sixteen).dy, epsilon: 1),
    );

    final beginner = find.descendant(
      of: dialog,
      matching: find.text('Beginner'),
    );
    final easy = find.descendant(of: dialog, matching: find.text('Easy'));
    final medium = find.descendant(of: dialog, matching: find.text('Medium'));
    final hard = find.descendant(of: dialog, matching: find.text('Hard'));
    final expert = find.descendant(of: dialog, matching: find.text('Expert'));
    expect(beginner, findsOneWidget);
    expect(easy, findsOneWidget);
    expect(medium, findsOneWidget);
    expect(hard, findsOneWidget);
    expect(expert, findsOneWidget);

    final firstRowY = tester.getCenter(beginner).dy;
    expect(tester.getCenter(easy).dy, moreOrLessEquals(firstRowY, epsilon: 1));
    expect(
      tester.getCenter(medium).dy,
      moreOrLessEquals(firstRowY, epsilon: 1),
    );

    final secondRowY = tester.getCenter(hard).dy;
    expect(
      tester.getCenter(expert).dy,
      moreOrLessEquals(secondRowY, epsilon: 1),
    );
    expect(secondRowY, greaterThan(firstRowY));

    final secondRowMidpoint =
        (tester.getCenter(hard).dx + tester.getCenter(expert).dx) / 2;
    expect(
      secondRowMidpoint,
      moreOrLessEquals(tester.getCenter(dialog).dx, epsilon: 2),
    );
  });
}
