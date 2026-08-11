import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/widgets/ux_notification_banner.dart';

void main() {
  testWidgets('notification banner remains readable at text scale 2.0', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: UxNotificationBanner(
                title: 'Connection',
                message: 'The operation could not be completed. Try again.',
                tone: UxNotificationTone.error,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Connection'), findsOneWidget);
    expect(
      find.text('The operation could not be completed. Try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation sheet returns the selected decision', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await UxConfirmationSheet.show(
                  context,
                  title: 'Restart game?',
                  message: 'Current progress will be cleared.',
                  confirmLabel: 'Restart',
                  cancelLabel: 'Keep playing',
                  destructive: true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Restart game?'), findsOneWidget);

    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
