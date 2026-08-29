import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ranked matchmaking carries the selected difficulty into pre-match', () {
    final matchmaking = File(
      'lib/features/duel/matchmaking_screen.dart',
    ).readAsStringSync();

    expect(
      matchmaking,
      contains(
        '_openOnlineRoom(roomId, requestedDifficulty: _difficulty.name)',
      ),
    );
    expect(
      matchmaking,
      contains('requestedDifficulty: requestedDifficulty'),
    );
  });

  test('pre-match terms use the authoritative room difficulty', () {
    final prematch = File(
      'lib/features/duel/pre_match_ready_screen.dart',
    ).readAsStringSync();

    expect(prematch, contains('final String? requestedDifficulty;'));
    expect(
      prematch,
      contains("final actualDifficulty = _normalizeDifficulty(_snapshot?.difficulty)"),
    );
    expect(
      prematch,
      contains('EconomyService.instance.entryFeeForDifficulty(actualDifficulty)'),
    );
    expect(
      prematch,
      contains('EconomyService.instance.winnerPotForDifficulty(actualDifficulty)'),
    );
    expect(prematch, contains('requested == actual'));
    expect(prematch, contains('PrematchMatchTermsCard('));
  });

  test('match terms card reuses localized economy labels and Coin asset', () {
    final card = File(
      'lib/features/duel/prematch_match_terms_card.dart',
    ).readAsStringSync();

    expect(card, contains("context.tr('entry_fee')"));
    expect(card, contains("context.tr('winner_pot')"));
    expect(card, contains("context.tr('coin_amount'"));
    expect(card, contains('DuelAsset.coin'));
    expect(card, contains('difficultyAdjustmentLabel'));
  });
}
