import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/features/social/platform_services_screen.dart';
import 'package:sudoku_game/localization/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.devoviastudio.sudoku/game_services');

  setUp(() {
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
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const PlatformServicesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Global ELO'), findsOneWidget);
    expect(find.text('Beginner'), findsOneWidget);
    expect(find.text('Achievement Showcase'), findsWidgets);
  });
}
