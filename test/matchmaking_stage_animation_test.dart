import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matchmaking stage keeps the approved animated duel composition', () {
    final source = File(
      'lib/features/duel/matchmaking_stage.dart',
    ).readAsStringSync();

    expect(source, contains('class MatchmakingStage extends StatefulWidget'));
    expect(source, contains('class _MatchmakingEnergyPainter extends CustomPainter'));
    expect(source, contains('RepaintBoundary('));
    expect(source, contains('MediaQuery.of(context).disableAnimations'));
    expect(source, contains('class _OpponentCard extends StatelessWidget'));
    expect(source, contains('class _MatchmakingActionButton extends StatefulWidget'));
    expect(source, isNot(contains('Random(')));
  });

  test('search and matched states stay inside one visual stage', () {
    final matchmaking = File(
      'lib/features/duel/matchmaking_screen.dart',
    ).readAsStringSync();
    final prematch = File(
      'lib/features/duel/pre_match_ready_screen.dart',
    ).readAsStringSync();

    expect(matchmaking, contains('MatchmakingStage('));
    expect(prematch, contains('MatchmakingStage('));
    expect(matchmaking, isNot(contains('class _SearchingStage')));
    expect(prematch, contains('initialCurrentPlayer'));
    expect(prematch, contains('HapticFeedback.mediumImpact()'));
  });

  test('visible rank points are never presented as Elo or generic rating', () {
    final source = File(
      'lib/features/duel/matchmaking_stage.dart',
    ).readAsStringSync();

    expect(source, contains("label: 'RP'"));
    expect(source, isNot(contains("context.tr('rating')")));
    expect(source, isNot(contains("context.tr('elo_unknown')")));
  });
}
