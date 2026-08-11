import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/data/local_progress_store.dart';
import 'package:sudoku_game/domain/sudoku_variant.dart';
import 'package:sudoku_game/services/economy_service.dart';

void main() {
  test('verified Coin delta reports only a real balance increase', () {
    expect(positiveCoinDelta(1000, 1025), 25);
    expect(positiveCoinDelta(1000, 1000), 0);
    expect(positiveCoinDelta(1000, 975), 0);
  });

  test(
    'practice bests improve independently and stay variant-scoped',
    () async {
      final store = await LocalProgressStore.createInMemory();

      await store.recordResult(
        puzzleId: 'practice-easy',
        seconds: 180,
        mistakes: 2,
        hints: 1,
        variant: SudokuVariant.classic9,
      );
      await store.recordResult(
        puzzleId: 'practice-easy',
        seconds: 150,
        mistakes: 3,
        hints: 2,
        variant: SudokuVariant.classic9,
      );
      await store.recordResult(
        puzzleId: 'practice-easy',
        seconds: 200,
        mistakes: 1,
        hints: 0,
        variant: SudokuVariant.classic9,
      );

      final classic9 = store.progressFor(
        'practice-easy',
        variant: SudokuVariant.classic9,
      );
      expect(classic9, isNotNull);
      expect(classic9!.bestSeconds, 150);
      expect(classic9.bestMistakes, 1);
      expect(classic9.bestHints, 0);

      await store.recordResult(
        puzzleId: 'practice-easy',
        seconds: 320,
        mistakes: 4,
        hints: 3,
        variant: SudokuVariant.classic16,
      );
      final classic16 = store.progressFor(
        'practice-easy',
        variant: SudokuVariant.classic16,
      );
      expect(classic16, isNotNull);
      expect(classic16!.bestSeconds, 320);
      expect(classic16.bestMistakes, 4);
      expect(classic16.bestHints, 3);
      expect(classic9.bestSeconds, 150);
    },
  );

  test('career practice cards use stable summary ids and show all bests', () {
    final source = File(
      'lib/features/career/career_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains("progressId: 'practice-\${difficulty.name}'"));
    expect(source, contains('progressId: puzzle.id'));
    expect(source, contains('progress.bestSeconds'));
    expect(source, contains('progress.bestHints'));
    expect(source, contains('progress.bestMistakes'));
    expect(source, contains('formatDuration(progress.bestSeconds)'));
    expect(source, contains('DuelAsset.coin'));
    expect(source, isNot(contains('Icons.monetization_on_rounded')));
  });

  test('game result uses verified Career Coin delta and no generic +25 ad', () {
    final game = File(
      'lib/features/game/enhanced_game_screen.dart',
    ).readAsStringSync();
    final economy = File(
      'lib/services/economy_service.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/career_reward_sync_service.dart',
    ).readAsStringSync();

    expect(game, contains('balanceBeforeCompletion'));
    expect(game, contains('completionCoinReward'));
    expect(game, contains('initialEarnedCoins'));
    expect(
      game,
      contains('GameInterstitialService.instance.recordAndMaybeShow'),
    );
    expect(game, contains('DuelAsset.coin'));
    expect(game, isNot(contains('watch_and_earn_coin')));
    expect(game, isNot(contains('claimCareerRewardedInterstitialCoins')));

    expect(
      economy,
      contains(
        'Future<int> claimCareerRewardedInterstitialCoins() async => 0;',
      ),
    );
    expect(economy, isNot(contains('confirmCareerAd(prepared.token)')));
    expect(sync, contains('_economy.claimCareer('));
    expect(sync, contains('await pending.future'));
  });

  test('active Coin balance and spend surfaces use the current Coin artwork', () {
    final sources = <String, String>{
      'career': File(
        'lib/features/career/career_hub_screen.dart',
      ).readAsStringSync(),
      'hint': File('lib/features/game/hint_economy.dart').readAsStringSync(),
      'wallet': File(
        'lib/features/economy/wallet_history_screen.dart',
      ).readAsStringSync(),
      'home': File(
        'lib/features/home/professional_home_screen.dart',
      ).readAsStringSync(),
      'onlineResult': File(
        'lib/features/duel/online_duel_screen.dart',
      ).readAsStringSync(),
    };

    for (final entry in sources.entries) {
      expect(
        entry.value,
        contains('DuelAsset.coin'),
        reason:
            '${entry.key} must use assets/images/ui/coin.png via DuelAsset.coin',
      );
    }
    expect(sources['hint'], isNot(contains('Icons.monetization_on_outlined')));
    expect(sources['career'], isNot(contains('Icons.monetization_on_rounded')));
  });

  test(
    'hint acquisition uses Economy V3 purchase, reward, and refill flows',
    () {
      final hint = File(
        'lib/features/game/hint_economy.dart',
      ).readAsStringSync();

      expect(hint, contains('EconomyV3Service.instance'));
      expect(hint, contains('consumeHintRefill()'));
      expect(hint, contains('purchaseHint('));
      expect(hint, contains('earnHintWithAd()'));
      expect(hint, isNot(contains('spendCareerContinue(')));
      expect(hint, isNot(contains('showRewarded()')));
    },
  );
}
