import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matchmaking stage keeps the approved responsive composition', () {
    final source = File(
      'lib/features/duel/matchmaking_stage.dart',
    ).readAsStringSync();

    expect(source, contains('class MatchmakingStage extends StatefulWidget'));
    expect(source, contains('SafeArea('));
    expect(source, contains('LayoutBuilder('));
    expect(source, contains('horizontalScale'));
    expect(source, contains('verticalScale'));
    expect(source, contains('class _ResponsiveDuelArena extends StatelessWidget'));
    expect(source, contains('constraints: const BoxConstraints(maxWidth: 520)'));
    expect(source, contains('RepaintBoundary('));
    expect(source, contains('class _MatchmakingEnergyPainter extends CustomPainter'));

    // The old diagonal/fractional composition was the source of iOS/Android
    // alignment and overflow differences. The approved screen keeps both cards
    // on one shared responsive arena row instead.
    expect(source, isNot(contains('Alignment(-.68')));
    expect(source, isNot(contains('Alignment(.68')));
    expect(source, isNot(contains('FractionallySizedBox(')));
    expect(source, isNot(contains('Random(')));
  });

  test('matchmaking animations stay subtle and reduced-motion aware', () {
    final source = File(
      'lib/features/duel/matchmaking_stage.dart',
    ).readAsStringSync();

    expect(source, contains('duration: const Duration(milliseconds: 5600)'));
    expect(source, contains('MediaQuery.of(context).disableAnimations'));
    expect(source, contains('class _SearchRadar extends StatelessWidget'));
    expect(source, contains('class _OpponentCard extends StatelessWidget'));
    expect(source, contains('AnimatedSwitcher('));
    expect(source, contains('class _MatchmakingActionButton extends StatefulWidget'));
  });

  test('selected difficulty is shown in the opponent-search header', () {
    final matchmaking = File(
      'lib/features/duel/matchmaking_screen.dart',
    ).readAsStringSync();

    expect(matchmaking, contains('MatchmakingStage('));
    expect(
      matchmaking,
      contains('difficultyLabel: context.strings.difficultyLabel(_difficulty)'),
    );
  });

  test('visible rank points are never presented as Elo or generic rating', () {
    final source = File(
      'lib/features/duel/matchmaking_stage.dart',
    ).readAsStringSync();

    expect(source, contains("'RP'"));
    expect(source, isNot(contains("context.tr('rating')")));
    expect(source, isNot(contains("context.tr('elo_unknown')")));
  });
}
