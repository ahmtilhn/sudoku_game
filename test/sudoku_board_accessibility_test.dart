import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/domain/sudoku.dart';
import 'package:sudoku_game/widgets/sudoku_board.dart';

void main() {
  testWidgets('selected user value keeps high contrast', (tester) async {
    final puzzle = SudokuPuzzle(
      id: 'selected-readability',
      difficulty: SudokuDifficulty.easy,
      puzzle: List<int>.filled(81, 0),
      solution: List<int>.filled(81, 1),
    );
    final board = List<int>.filled(81, 0)..[0] = 5;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 360,
              child: SudokuBoard(
                puzzle: puzzle,
                board: board,
                selectedIndex: 0,
                onCellTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final value = tester.widget<Text>(find.text('5'));
    expect(value.style?.color, const Color(0xFFFFFFFF));
    expect(value.style?.fontWeight, FontWeight.w900);
    expect(tester.takeException(), isNull);
  });

  testWidgets('classic16 renders numeric values and a 4 by 4 note grid', (
    tester,
  ) async {
    final puzzle = SudokuPuzzle(
      id: 'numeric-16',
      difficulty: SudokuDifficulty.medium,
      puzzle: List<int>.filled(256, 0),
      solution: List<int>.generate(256, (index) => (index % 16) + 1),
      size: 16,
      boxRows: 4,
      boxColumns: 4,
    );
    final board = List<int>.filled(256, 0)
      ..[0] = 10
      ..[1] = 16;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 640,
              child: SudokuBoard(
                puzzle: puzzle,
                board: board,
                selectedIndex: 2,
                notes: const <int, Set<int>>{
                  2: <int>{10, 16},
                },
                onCellTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('10'), findsNWidgets(2));
    expect(find.text('16'), findsNWidgets(2));
    expect(find.text('A'), findsNothing);
    expect(find.text('G'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
