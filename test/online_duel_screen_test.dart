import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/core/app_theme.dart';
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

  testWidgets('online duel fits required compact viewports', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const <Size>[
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
    ]) {
      await _pumpOnlineDuel(tester, size: size);

      expect(find.byType(ListView), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('I am ready'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('sudoku-cell-2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('number-1')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('online duel supports theme contrast text scale and RTL', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const variants = <_ViewportVariant>[
      _ViewportVariant(
        label: 'text scale 1.3 390x844',
        size: Size(390, 844),
        brightness: Brightness.dark,
        textScale: 1.3,
      ),
      _ViewportVariant(
        label: 'light 360x640',
        size: Size(360, 640),
        brightness: Brightness.light,
      ),
      _ViewportVariant(
        label: 'dark 360x640',
        size: Size(360, 640),
        brightness: Brightness.dark,
      ),
      _ViewportVariant(
        label: 'high contrast 390x844',
        size: Size(390, 844),
        brightness: Brightness.light,
        highContrast: true,
      ),
      _ViewportVariant(
        label: 'rtl 390x844',
        size: Size(390, 844),
        brightness: Brightness.light,
        textDirection: TextDirection.rtl,
      ),
    ];

    for (final variant in variants) {
      await _pumpOnlineDuel(
        tester,
        size: variant.size,
        brightness: variant.brightness,
        highContrast: variant.highContrast,
        textScale: variant.textScale,
        textDirection: variant.textDirection,
      );

      expect(tester.takeException(), isNull, reason: variant.label);
      expect(find.text('I am ready'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('number-9')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('online active state has one timer no turn banner or ELO badge', (
    tester,
  ) async {
    await _pumpOnlineDuel(tester, size: const Size(390, 844), status: 'active');

    expect(find.text('Your turn'), findsNothing);
    expect(find.text("Opponent's turn"), findsNothing);
    expect(find.textContaining('Move time'), findsNothing);
    expect(find.textContaining('ELO'), findsNothing);
    expect(find.byIcon(Icons.military_tech_outlined), findsNothing);
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byType(RepaintBoundary), findsWidgets);
    expect(find.text('You'), findsWidgets);
    expect(find.text('Bob'), findsWidgets);
    expect(find.text('s'), findsOneWidget);
  });

  testWidgets('active header aligns timer, puts names below avatars and scores inward', (tester) async {
    await _pumpOnlineDuel(tester, size: const Size(390, 844), status: 'active');

    final timerCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('online-turn-timer')),
    );
    final avatarACenter = tester.getCenter(
      find.byKey(const ValueKey<String>('duel-avatar-A')),
    );
    final avatarBCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('duel-avatar-B')),
    );
    expect((timerCenter.dy - avatarACenter.dy).abs(), lessThan(12));
    expect((timerCenter.dy - avatarBCenter.dy).abs(), lessThan(12));

    expect(find.byKey(const ValueKey<String>('duel-name-A')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('duel-name-B')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('duel-score-A')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('duel-score-B')), findsOneWidget);
  });

  testWidgets('paused online duel blocks input and shows reconnect state', (tester) async {
    await _pumpOnlineDuel(
      tester,
      size: const Size(390, 844),
      status: 'paused',
      opponentConnected: false,
    );

    expect(find.text('Opponent is connecting'), findsOneWidget);
    final numberButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('number-1')),
    );
    expect(numberButton.onPressed, isNull);
  });

  testWidgets('opponent turn keeps board readable and disables number input', (
    tester,
  ) async {
    await _pumpOnlineDuel(
      tester,
      size: const Size(390, 844),
      currentTurnSeat: 'B',
    );

    expect(find.byType(ColorFiltered), findsNothing);
    final numberButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('number-1')),
    );
    expect(numberButton.onPressed, isNull);
  });
}

Future<void> _pumpOnlineDuel(
  WidgetTester tester, {
  required Size size,
  Brightness brightness = Brightness.light,
  bool highContrast = false,
  double textScale = 1,
  TextDirection textDirection = TextDirection.ltr,
  String status = 'ready_window',
  String currentTurnSeat = 'A',
  bool opponentConnected = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final strings = AppStrings.forTesting();
  final transport = FakeOnlineDuelTransport();
  final controller = OnlineDuelController(transport);

  await tester.pumpWidget(
    AppStringsScope(
      strings: strings,
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark(highContrast: highContrast)
            : AppTheme.light(highContrast: highContrast),
        builder: (context, child) {
          final data = MediaQuery.of(context).copyWith(
            highContrast: highContrast,
            textScaler: TextScaler.linear(textScale),
          );
          return MediaQuery(
            data: data,
            child: Directionality(
              textDirection: textDirection,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: OnlineDuelScreen(roomId: 'room', controller: controller),
      ),
    ),
  );
  await tester.pump();
  transport.emit(
    _event(
      'snapshot',
      _snapshot(
        status: status,
        currentTurnSeat: currentTurnSeat,
        opponentConnected: opponentConnected,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _ViewportVariant {
  const _ViewportVariant({
    required this.label,
    required this.size,
    required this.brightness,
    this.highContrast = false,
    this.textScale = 1,
    this.textDirection = TextDirection.ltr,
  });

  final String label;
  final Size size;
  final Brightness brightness;
  final bool highContrast;
  final double textScale;
  final TextDirection textDirection;
}

OnlineDuelEvent _event(String type, Map<String, dynamic> payload) {
  return OnlineDuelEvent(
    type: type,
    revision: 2,
    serverTime: DateTime.fromMillisecondsSinceEpoch(1000),
    payload: payload,
  );
}

Map<String, dynamic> _snapshot({
  String status = 'active',
  String currentTurnSeat = 'A',
  bool opponentConnected = true,
}) {
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
        'connected': opponentConnected,
        'disconnectDeadline': opponentConnected
            ? null
            : now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
      },
    },
    'puzzle': puzzle,
    'board': puzzle,
    'scores': {'A': 0, 'B': 0},
    'mistakes': {'A': 0, 'B': 0},
    'correctMoves': {'A': 0, 'B': 0},
    'timeouts': {'A': 0, 'B': 0},
    'currentTurnSeat': currentTurnSeat,
    'turnNumber': 1,
    'readyDeadline': now
        .add(const Duration(seconds: 10))
        .millisecondsSinceEpoch,
    'turnDeadline': status == 'paused'
        ? null
        : now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    'pausedTurnRemainingMs': status == 'paused' ? 17000 : null,
    'serverTime': 1000,
    'revision': 2,
  };
}
