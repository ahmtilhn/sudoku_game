import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/widgets/duel_asset_icon.dart';
import 'package:sudoku_game/widgets/game_pause_menu.dart';

void main() {
  testWidgets('pause menu fits a compact phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamePauseMenu(
            asset: DuelAsset.board16Pro,
            title: 'Paused',
            subtitle: 'Your game is saved. Continue when you are ready.',
            variantLabel: '16×16 · 1–16',
            difficultyLabel: 'Medium',
            timeLabel: 'Time',
            timeValue: '12:34',
            mistakesLabel: 'Mistakes',
            mistakesValue: '1/3',
            hintsLabel: 'Hints',
            hintsValue: '2',
            resumeLabel: 'Continue',
            restartLabel: 'Restart',
            menuLabel: 'Main menu',
            onResume: _noop,
            onRestart: _noop,
            onMenu: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey<String>('game-pause-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('pause-resume')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('pause-restart')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('pause-menu')), findsOneWidget);
    expect(find.text('16×16 · 1–16'), findsOneWidget);
  });
}

void _noop() {}
