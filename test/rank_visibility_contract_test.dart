import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matchmaking presentation uses visible RP terminology only', () {
    final stage = File(
      'lib/features/duel/matchmaking_stage.dart',
    ).readAsStringSync();
    final matchmaking = File(
      'lib/features/duel/matchmaking_screen.dart',
    ).readAsStringSync();
    final prematch = File(
      'lib/features/duel/pre_match_ready_screen.dart',
    ).readAsStringSync();

    expect(stage.contains("context.tr('rating')"), isFalse);
    expect(stage.contains('player.rating'), isFalse);
    expect(stage.contains('final int? rating;'), isFalse);
    expect(stage.contains('final int? rankPoints;'), isTrue);
    expect(stage.contains("label: 'RP'"), isTrue);
    expect(matchmaking.contains('rating: profile.rankPoints'), isFalse);
    expect(matchmaking.contains('rankPoints: profile.rankPoints'), isTrue);
    expect(prematch.contains('rating: profile.rankPoints'), isFalse);
    expect(prematch.contains('rankPoints: profile.rankPoints'), isTrue);
  });

  test('active social screen does not render the legacy Elo profile card', () {
    final social = File(
      'lib/features/social/platform_social_screen.dart',
    ).readAsStringSync();

    expect(social.contains('CompetitiveProfileCard('), isFalse);
    expect(social.contains('currentElo:'), isFalse);
    expect(social.contains('_competitiveProfile'), isFalse);
  });
}
