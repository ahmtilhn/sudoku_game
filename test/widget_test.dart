import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/app.dart';
import 'package:sudoku_game/data/local_progress_store.dart';

void main() {
  testWidgets('home screen exposes the main game modes', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalProgressStore.create();

    await tester.pumpWidget(SudokuApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Kariyer'), findsOneWidget);
    expect(find.text('Yerel Düello'), findsOneWidget);
    expect(find.text('Günlük Sudoku'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
