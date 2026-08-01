import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/domain/sudoku.dart';
import 'package:sudoku_game/features/game/game_screen.dart';
import 'package:sudoku_game/localization/app_strings.dart';

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

  testWidgets('hinted cells stay locked while player moves remain undoable', (
    tester,
  ) async {
    final strings = await AppStrings.load();

    await tester.pumpWidget(
      AppStringsScope(
        strings: strings,
        child: MaterialApp(
          home: GameScreen(
            puzzle: _hintPuzzle,
            hintBalanceProvider: () => 3,
            onConsumeHint: () async => true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('action-hint')));
    await tester.pump();

    expect(_cellTextFinder(1, '2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sudoku-cell-1')));
    await tester.tap(find.byKey(const ValueKey<String>('action-erase')));
    await tester.pump();
    expect(_cellTextFinder(1, '2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('sudoku-cell-2')));
    await tester.tap(find.byKey(const ValueKey<String>('number-3')));
    await tester.pump();
    expect(_cellTextFinder(2, '3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('action-undo')));
    await tester.pump();

    expect(_cellTextFinder(2, '3'), findsNothing);
    expect(_cellTextFinder(1, '2'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('action-undo')), findsNothing);

    await _disposeGame(tester);
  });
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
