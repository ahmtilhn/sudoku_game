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
    'assets/images/ui/coin.png',
    'assets/images/ui/gift.png',
    'assets/images/ui/diamond.png',
    'assets/images/ui/shield.png',
    'assets/images/ui/victory_trophy.png',
    'assets/images/ui/defeat_trophy.png',
    'assets/images/ui/leaderboard.png',
    'assets/images/ui/store_coins_100.png',
    'assets/images/ui/store_coins_500.png',
    'assets/images/ui/store_coins_1000.png',
    'assets/images/ui/store_coins_5000.png',
    'assets/images/ui/store_coins_10000.png',
    'assets/images/ui/store_coins_50000.png',
    'assets/images/ui/store_coins_100000.png',
    'assets/images/ui/store_no_ads.png',
  ];

  test('all generated production artwork exists', () {
    for (final asset in generatedAssets) {
      expect(File(asset).existsSync(), isTrue, reason: 'Missing $asset');
    }
  });

  test('DuelAsset catalog points economy artwork at current PNGs', () {
    final source = File('lib/widgets/duel_asset_icon.dart').readAsStringSync();

    for (final asset in generatedAssets) {
      expect(
        source,
        contains("'$asset'"),
        reason: 'Catalog does not use $asset',
      );
    }
    expect(source, contains('static const dailyRewardPro = gift;'));
    expect(source, contains('static const walletCoinStackPro = coin;'));
    expect(source, contains('static const removeAdsPro = shield;'));
    expect(source, contains('static const Set<String> fullColorArtwork'));
    expect(source, contains('preserveOriginalColor ? null : color'));
  });

  test('home is centered and consumes current coin and gift artwork', () {
    final home = File(
      'lib/features/home/professional_home_screen.dart',
    ).readAsStringSync();

    expect(home, contains('DuelAsset.homePlayScene'));
    expect(home, contains('DuelAsset.homeDuelScene'));
    expect(home, contains('DuelAsset.homeCareerScene'));
    expect(home, contains('DuelAsset.homeFriendsScene'));
    expect(home, contains('DuelAsset.homeStoreScene'));
    expect(home, contains('DuelAsset.homeProfileScene'));
    expect(home, contains('DuelAsset.dailyRewardPro'));
    expect(home, contains('DuelAsset.coin'));
    expect(home, contains('constraints: const BoxConstraints(maxWidth: 760)'));
    expect(home, contains('child: Center('));
  });

  test('coin store uses current economy artwork without fixed overflow', () {
    final store = File(
      'lib/features/economy/coin_store_screen.dart',
    ).readAsStringSync();

    expect(store, contains('DuelAsset.coinStoreBalancePro'));
    expect(store, contains('DuelAsset.storeCoins100'));
    expect(store, contains('DuelAsset.storeCoins500'));
    expect(store, contains('DuelAsset.storeCoins1000'));
    expect(store, contains('DuelAsset.storeCoins5000'));
    expect(store, contains('DuelAsset.storeCoins10000'));
    expect(store, contains('DuelAsset.storeCoins50000'));
    expect(store, contains('DuelAsset.storeCoins100000'));
    expect(store, contains('DuelAsset.storeNoAds'));
    expect(store, contains('DuelAsset.diamond'));
    expect(store, contains('_CoinPackageCard'));
    expect(store, isNot(contains('width: 360')));
  });

  test('leaderboard and outcome screens consume production artwork', () {
    final leaderboards = File(
      'lib/features/duel/leaderboards_screen.dart',
    ).readAsStringSync();
    final outcomes = File('lib/widgets/ux_feedback.dart').readAsStringSync();
    final soloGame = File(
      'lib/features/game/enhanced_game_screen.dart',
    ).readAsStringSync();

    expect(leaderboards, contains('DuelAsset.leaderboardCrownPro'));
    expect(outcomes, contains('DuelAsset.resultVictoryTrophyPro'));
    expect(outcomes, contains('DuelAsset.resultDefeatTrophyPro'));
    expect(soloGame, contains('DuelAsset.resultDefeatTrophyPro'));
  });
}
