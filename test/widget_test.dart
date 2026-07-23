import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/app.dart';
import 'package:sudoku_game/data/local_progress_store.dart';
import 'package:sudoku_game/localization/app_strings.dart';

void main() {
  testWidgets('home screen exposes the main game modes', (tester) async {
    final store = await LocalProgressStore.createInMemory();
    final strings = await AppStrings.load();

    await tester.pumpWidget(SudokuApp(store: store, strings: strings));
    await tester.pumpAndSettle();

    expect(find.text('Career'), findsOneWidget);
    expect(find.text('Local Duel'), findsOneWidget);
    expect(find.text('Daily Sudoku'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
