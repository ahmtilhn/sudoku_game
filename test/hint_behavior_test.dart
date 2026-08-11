import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sudoku_game/domain/sudoku.dart';
import 'package:sudoku_game/features/game/game_screen.dart';
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
    'a rapid double tap consumes one hint and the hinted cell stays locked',
    (tester) async {
      final strings = AppStrings.forTesting();
      final completer = Completer<bool>();
      addTearDown(() {
        if (!completer.isCompleted) completer.complete(false);
      });
      var consumeCalls = 0;

      await tester.pumpWidget(
        AppStringsScope(
          strings: strings,
          child: MaterialApp(
            home: GameScreen(
              puzzle: _hintPuzzle,
              hintBalanceProvider: () => 3,
              onConsumeHint: () {
                consumeCalls++;
                return completer.future;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final hintButton = find.byKey(const ValueKey<String>('action-hint'));
      expect(hintButton, findsOneWidget);
      await tester.tap(hintButton);
      await tester.tap(hintButton);
      await tester.pump();

      expect(consumeCalls, 1);

      completer.complete(true);
      await tester.pump();
      await tester.pump();

      expect(_cellTextFinder(1, '2'), findsOneWidget);
      expect(_cellTextFinder(2, '3'), findsNothing);
      expect(find.byKey(const ValueKey<String>('action-undo')), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('sudoku-cell-1')));
      await tester.tap(find.byKey(const ValueKey<String>('action-erase')));
      await tester.pump();

      expect(_cellTextFinder(1, '2'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('action-undo')), findsNothing);

      await _disposeGame(tester);
    },
  );
}

Future<void> _disposeGame(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Finder _cellTextFinder(int index, String value) {
  return find.descendant(
    of: find.byKey(ValueKey<String>('sudoku-cell-$index')),
    matching: find.text(value),
  );
}

const SudokuPuzzle _hintPuzzle = SudokuPuzzle(
  id: 'hint-test-4x4',
  title: 'Hint test',
  difficulty: SudokuDifficulty.beginner,
  size: 4,
  boxRows: 2,
  boxColumns: 2,
  puzzle: <int>[1, 0, 0, 4, 0, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
  solution: <int>[1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
);
