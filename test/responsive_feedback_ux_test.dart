import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/widgets/number_pad.dart';
import 'package:sudoku_game/widgets/ux_feedback.dart';

void main() {
  testWidgets('shared outcome remains scrollable at 320px and 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: UxOutcomeSheet(
                icon: Icons.emoji_events_rounded,
                title: 'Match completed',
                subtitle: 'Your result and rewards are ready.',
                metrics: const <Widget>[
                  UxMetricTile(label: 'Rating', value: '+24'),
                  UxMetricTile(label: 'Coins', value: '+50'),
                  UxMetricTile(label: 'Mistakes', value: '1'),
                ],
                primaryLabel: 'Continue',
                onPrimary: _noop,
                secondaryLabel: 'Play again',
                onSecondary: _noop,
                tertiaryLabel: 'Main menu',
                onTertiary: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Match completed'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.ensureVisible(find.text('Main menu'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('16x16 number pad remains usable on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      AppStringsScope(
        strings: AppStrings.forTesting(),
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              bottomNavigationBar: NumberPadDock(
                child: NumberPad(
                  maxValue: 16,
                  onNumber: (_) {},
                  onErase: _noop,
                  onToggleNotes: _noop,
                  onUndo: _noop,
                  onHint: _noop,
                ),
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final symbol in <String>['1', '9', '10', '16']) {
      expect(find.text(symbol), findsOneWidget);
    }
    expect(find.text('A'), findsNothing);
    expect(find.text('G'), findsNothing);
    expect(find.byKey(const ValueKey<String>('number-16')), findsOneWidget);
  });

  test(
    'daily reward dialogs are constrained and scrollable on compact screens',
    () {
      final home = File(
        'lib/features/home/professional_home_screen.dart',
      ).readAsStringSync();
      final gate = File(
        'lib/features/economy/daily_reward_gate.dart',
      ).readAsStringSync();

      expect(home, contains('maxHeight: size.height - (verticalInset * 2)'));
      expect(home, contains('SingleChildScrollView'));
      expect(home, contains('constraints.maxWidth >= 280'));
      expect(home, contains('constraints.maxWidth < 360'));
      expect(home, contains('overflow: TextOverflow.ellipsis'));

      expect(gate, contains('maxHeight: size.height - (compact ? 20 : 48)'));
      expect(gate, contains('SingleChildScrollView'));
      expect(gate, contains('overflow: TextOverflow.ellipsis'));
    },
  );

  test('coin store uses responsive grid and compact purchase cards', () {
    final source = File(
      'lib/features/economy/coin_store_screen.dart',
    ).readAsStringSync();

    expect(source, contains('constraints.maxWidth >= 900'));
    expect(source, contains('constraints.maxWidth >= 560'));
    expect(source, contains('horizontalPadding'));
    expect(source, contains('gridAspectRatio'));
    expect(source, contains('final stacked = constraints.maxWidth < 380'));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.stretch'));
    expect(source, contains('overflow: TextOverflow.ellipsis'));
  });
}

void _noop() {}
