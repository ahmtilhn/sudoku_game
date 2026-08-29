import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/core/app_theme.dart';
import 'package:sudoku_game/features/duel/pre_match_ready_screen.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/services/online_duel_controller.dart';
import 'package:sudoku_game/services/online_duel_models.dart';
import 'package:sudoku_game/services/online_duel_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localizationChannel = MethodChannel('com.devovia.sudoku/localization');

  setUp(() {
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

  testWidgets('ready screen exposes emotes when an opponent is present', (
    tester,
  ) async {
    await _pumpReady(tester);

    expect(
      find.byKey(const ValueKey<String>('ready-screen-emotes')),
      findsOneWidget,
    );

    expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
  });

  testWidgets('ready screen renders incoming opponent emote', (tester) async {
    final transport = await _pumpReady(tester);

    transport.emit(_event('emote', {'seat': 'B', 'emoteId': 'respect'}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byIcon(Icons.front_hand_rounded), findsOneWidget);
  });
}

Future<FakeOnlineDuelTransport> _pumpReady(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final transport = FakeOnlineDuelTransport();
  final controller = OnlineDuelController(transport);

  await tester.pumpWidget(
    AppStringsScope(
      strings: AppStrings.forTesting(),
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: PreMatchReadyScreen(roomId: 'room', controller: controller),
      ),
    ),
  );
  await tester.pump();
  transport.emit(_event('snapshot', _snapshot()));
  await tester.pump();
  await tester.pump();
  return transport;
}

OnlineDuelEvent _event(String type, Map<String, dynamic> payload) {
  return OnlineDuelEvent(
    type: type,
    revision: 2,
    serverTime: DateTime.fromMillisecondsSinceEpoch(1000),
    payload: payload,
  );
}

Map<String, dynamic> _snapshot() {
  final puzzle = List<int>.filled(81, 0)..[0] = 1;
  final now = DateTime.now();
  return {
    'roomId': 'room',
    'matchId': 'match',
    'mode': 'ranked',
    'difficulty': 'easy',
    'status': 'ready_window',
    'youSeat': 'A',
    'players': {
      'A': {
        'publicId': 'a',
        'username': 'alice',
        'displayName': 'Alice',
        'avatarKey': 'default',
        'ready': false,
        'screenLoaded': true,
        'connected': true,
      },
      'B': {
        'publicId': 'b',
        'username': 'bob',
        'displayName': 'Bob',
        'avatarKey': 'default',
        'ready': false,
        'screenLoaded': true,
        'connected': true,
      },
    },
    'puzzle': puzzle,
    'board': puzzle,
    'scores': {'A': 0, 'B': 0},
    'mistakes': {'A': 0, 'B': 0},
    'correctMoves': {'A': 0, 'B': 0},
    'timeouts': {'A': 0, 'B': 0},
    'currentTurnSeat': 'A',
    'turnNumber': 1,
    'readyDeadline': now
        .add(const Duration(seconds: 10))
        .millisecondsSinceEpoch,
    'turnDeadline': now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    'serverTime': 1000,
    'revision': 2,
  };
}
