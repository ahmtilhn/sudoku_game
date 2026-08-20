import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('post-game ads use rewarded interstitial with no legacy frequency gate', () {
    final source = File(
      'lib/services/game_interstitial_service.dart',
    ).readAsStringSync();

    expect(source, contains('earnHintWithRewardedInterstitial()'));
    expect(source, contains("'post-game-rewarded-interstitial-offer'"));
    expect(source, contains("sheetContext.tr('skip')"));
    expect(source, contains("'+1 \${sheetContext.tr('hints')}'"));
    expect(source, isNot(contains('InterstitialAd.load(')));
    expect(source, isNot(contains('_globalCooldown')));
    expect(source, isNot(contains('_eligibleResults')));
  });

  test('RewardedAd remains separate from rewarded interstitial and powers x2', () {
    final ads = File('lib/services/ads_service.dart').readAsStringSync();
    final flow = File(
      'lib/services/game_interstitial_service.dart',
    ).readAsStringSync();
    final economy = File(
      'lib/services/economy_v3_service.dart',
    ).readAsStringSync();

    expect(ads, contains('Future<bool> showRewarded('));
    expect(ads, contains('Future<bool> showRewardedInterstitial('));
    expect(economy, contains('_ads.showRewarded('));
    expect(economy, contains('_ads.showRewardedInterstitial('));
    expect(flow, contains('doubleCareerReward('));
    expect(flow, contains('earnHintWithAd()'));
    expect(flow, contains("'career-x2-rewarded-offer'"));
    expect(flow, contains("'offline-x2-hint-rewarded-offer'"));
  });

  test('Career x2 amount is derived from the real server completion reward', () {
    final backend = File(
      'backend/social_worker/src/economy_v3_career_hints.ts',
    ).readAsStringSync();
    final routes = File(
      'backend/social_worker/src/economy_v3.ts',
    ).readAsStringSync();

    expect(backend, contains("source = 'career_completion'"));
    expect(backend, contains('const amount = Number(completion?.amount ?? 0);'));
    expect(backend, contains("rewardKey: `v3_career_double:"));
    expect(backend, contains("source: 'career_double_rewarded_ad'"));
    expect(backend, contains("ledgerReason: 'career_rewarded_ad'"));
    expect(routes, contains("'/v1/economy/v3/career/double/prepare'"));
    expect(routes, contains("'/v1/economy/v3/career/double/confirm'"));
    expect(routes, contains('assertProductionRewardConfirmedBySsv'));
  });

  test('production SSV allowlist contains rewarded and rewarded-interstitial ids', () {
    final config = File(
      'backend/social_worker/wrangler.production.toml',
    ).readAsStringSync();

    expect(config, contains('ca-app-pub-8422988604275177/3474727600'));
    expect(config, contains('ca-app-pub-8422988604275177/4787809275'));
    expect(config, contains('ca-app-pub-8422988604275177/3366916396'));
    expect(config, contains('ca-app-pub-8422988604275177/4982984468'));
  });

  test('online duel flow does not invoke the offline post-game ad gate', () {
    final onlineSources = <String>[
      'lib/features/duel/online_duel_screen.dart',
      'lib/features/duel/pre_match_ready_screen.dart',
      'lib/features/duel/matchmaking_screen.dart',
    ];

    for (final path in onlineSources) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('GameInterstitialService.instance.recordAndMaybeShow')),
        reason: '$path must remain ad-free for online play',
      );
    }
  });
}
