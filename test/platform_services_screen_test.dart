import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/features/social/platform_services_screen.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/services/platform_game_services.dart';
import 'package:sudoku_game/widgets/duel_asset_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.devoviastudio.sudoku/game_services');

  setUp(() {
    PlatformGameServices.instance.authenticated.value = false;
    PlatformGameServices.instance.localPlayer.value = null;
    PlatformGameServices.instance.lastError.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'isConfigured' => true,
            'isAuthenticated' => true,
            'getLocalPlayer' => <String, Object?>{
              'platform': 'google_play_games',
              'playerId': 'player-1',
              'displayName': 'Responsive Player',
            },
            'authenticate' => true,
            'showLeaderboard' => true,
            'showAchievements' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('refreshes platform connection when opened', (tester) async {
    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: const MaterialApp(home: PlatformServicesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Global ELO'), findsOneWidget);
    expect(PlatformGameServices.instance.authenticated.value, isTrue);
    expect(
      PlatformGameServices.instance.localPlayer.value?.playerId,
      'player-1',
    );
  });

  testWidgets('leaderboard hub fits 320x568 at 2x text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const PlatformServicesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Global ELO'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(DuelAssetIcon), findsAtLeastNWidgets(2));

    final scrollable = find.byType(Scrollable).first;
    final scrollState = tester.state<ScrollableState>(scrollable);
    expect(scrollState.position.maxScrollExtent, greaterThan(0));

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(scrollState.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
