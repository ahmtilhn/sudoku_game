import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const generatedAssets = <String>[
    'assets/images/ui/home_play.png',
    'assets/images/ui/home_online_duel.png',
    'assets/images/ui/home_career.png',
    'assets/images/ui/home_friends.png',
    'assets/images/ui/home_coin_store.png',
    'assets/images/ui/home_profile.png',
    'assets/images/ui/coin_stack.png',
    'assets/images/ui/daily_reward.png',
    'assets/images/ui/victory_trophy.png',
    'assets/images/ui/defeat_trophy.png',
    'assets/images/ui/leaderboard.png',
  ];

  test('all generated production artwork exists', () {
    for (final asset in generatedAssets) {
      expect(File(asset).existsSync(), isTrue, reason: 'Missing $asset');
    }
  });

  test('DuelAsset catalog points production artwork at generated PNGs', () {
    final source = File('lib/widgets/duel_asset_icon.dart').readAsStringSync();

    for (final asset in generatedAssets) {
      expect(source, contains("'$asset'"), reason: 'Catalog does not use $asset');
    }
  });

  test('home, leaderboard, and outcome screens consume production assets', () {
    final home = File(
      'lib/features/home/professional_home_screen.dart',
    ).readAsStringSync();
    final leaderboards = File(
      'lib/features/duel/leaderboards_screen.dart',
    ).readAsStringSync();
    final outcomes = File('lib/widgets/ux_feedback.dart').readAsStringSync();
    final soloGame = File(
      'lib/features/game/enhanced_game_screen.dart',
    ).readAsStringSync();

    expect(home, contains('DuelAsset.homePlayScene'));
    expect(home, contains('DuelAsset.homeDuelScene'));
    expect(home, contains('DuelAsset.homeCareerScene'));
    expect(home, contains('DuelAsset.homeFriendsScene'));
    expect(home, contains('DuelAsset.homeStoreScene'));
    expect(home, contains('DuelAsset.homeProfileScene'));
    expect(home, contains('DuelAsset.dailyRewardPro'));
    expect(home, contains('DuelAsset.walletCoinStackPro'));
    expect(leaderboards, contains('DuelAsset.leaderboardCrownPro'));
    expect(outcomes, contains('DuelAsset.resultVictoryTrophyPro'));
    expect(outcomes, contains('DuelAsset.resultDefeatTrophyPro'));
    expect(soloGame, contains('DuelAsset.resultVictoryTrophyPro'));
  });
}
