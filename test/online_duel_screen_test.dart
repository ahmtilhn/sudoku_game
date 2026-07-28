import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/features/duel/online_duel_screen.dart';
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

  testWidgets('online duel fits first viewport without page scroll or slider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final strings = AppStrings.forTesting();
    final transport = FakeOnlineDuelTransport();
    final controller = OnlineDuelController(transport);

    await tester.pumpWidget(
      AppStringsScope(
        strings: strings,
        child: MaterialApp(
          home: OnlineDuelScreen(roomId: 'room', controller: controller),
        ),
      ),
    );
    await tester.pump();
    transport.emit(_event('snapshot', _snapshot(status: 'ready_window')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ListView), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('I am ready'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sudoku-cell-2')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('number-1')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

OnlineDuelEvent _event(String type, Map<String, dynamic> payload) {
  return OnlineDuelEvent(
    type: type,
    revision: 2,
    serverTime: DateTime.fromMillisecondsSinceEpoch(1000),
    payload: payload,
  );
}

Map<String, dynamic> _snapshot({String status = 'active'}) {
  final puzzle = List<int>.filled(81, 0)..[0] = 1;
  final now = DateTime.now();
  return {
    'roomId': 'room',
    'matchId': 'match',
    'mode': 'ranked',
    'difficulty': 'easy',
    'status': status,
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
