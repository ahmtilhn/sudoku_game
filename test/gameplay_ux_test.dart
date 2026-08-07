import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sudoku_game/data/local_progress_store.dart';
import 'package:sudoku_game/domain/sudoku.dart';
import 'package:sudoku_game/features/game/enhanced_game_screen.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/widgets/sudoku_board.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('selected user value uses readable white foreground', (
    tester,
  ) async {
    final puzzle = _miniPuzzle();
    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 320,
                child: SudokuBoard(
                  puzzle: puzzle,
                  board: puzzle.solution,
                  selectedIndex: 1,
                  onCellTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final selectedCell = find.byKey(const ValueKey<String>('sudoku-cell-1'));
    final selectedValue = find.descendant(
      of: selectedCell,
      matching: find.text('2'),
    );
    expect(selectedValue, findsOneWidget);

    final text = tester.widget<Text>(selectedValue);
    expect(text.style?.color, const Color(0xFFFFFFFF));
    expect(text.style?.fontWeight, FontWeight.w900);
  });

  testWidgets('notes render inside the selected cell and erase clears them', (
    tester,
  ) async {
    final store = await LocalProgressStore.createInMemory();
    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: MaterialApp(
          home: EnhancedGameScreen(
            puzzle: _miniPuzzle(),
            store: store,
            allowNotes: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final emptyCell = find.byKey(const ValueKey<String>('sudoku-cell-1'));
    await tester.tap(emptyCell);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('action-notes')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('number-2')));
    await tester.pump();

    expect(
      find.descendant(of: emptyCell, matching: find.text('2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('action-erase')));
    await tester.pump();

    expect(
      find.descendant(of: emptyCell, matching: find.text('2')),
      findsNothing,
    );
  });

  testWidgets('pause stops interaction and exposes all requested actions', (
    tester,
  ) async {
    final store = await LocalProgressStore.createInMemory();
    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: MaterialApp(
          home: EnhancedGameScreen(
            puzzle: _miniPuzzle(),
            store: store,
            mistakeLimit: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('action-pause')));
    await tester.pumpAndSettle();

    expect(find.text('Game paused'), findsWidgets);
    expect(find.text('Continue'), findsWidgets);
    expect(find.text('Restart from the beginning'), findsOneWidget);
    expect(find.text('Main menu'), findsOneWidget);

    final numberButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('number-2')),
    );
    expect(numberButton.onPressed, isNull);

    final continueButton = find.widgetWithText(FilledButton, 'Continue').last;
    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('Game paused'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

SudokuPuzzle _miniPuzzle() {
  const solution = <int>[1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1];
  return const SudokuPuzzle(
    id: 'ux-test-mini',
    title: 'Mini',
    difficulty: SudokuDifficulty.easy,
    puzzle: <int>[1, 0, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
    solution: solution,
    size: 4,
    boxRows: 2,
    boxColumns: 2,
  );
}
