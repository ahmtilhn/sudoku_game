import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS rewarded ads can fall back to rewarded interstitial inventory', () {
    final source = File('lib/services/ads_service.dart').readAsStringSync();

    expect(source, contains("_iosRewardedProductionId ="));
    expect(source, contains("_iosRewardedInterstitialProductionId ="));
    expect(source, contains("if (Platform.isIOS)"));
    expect(
      source,
      contains(
        "return showRewardedInterstitial(verificationToken: verificationToken);",
      ),
    );
    expect(source, contains("Rewarded ad unavailable on iOS"));
  });

  test('iOS ad initialization is resilient to UMP and ATT native errors', () {
    final source = File('lib/services/ads_service.dart').readAsStringSync();

    expect(
      source,
      contains("ConsentInformation.instance.requestConsentInfoUpdate("),
    );
    expect(source, contains("UMP consent update threw"));
    expect(source, contains("Ads consent flow failed"));
    expect(source, contains("ATT request skipped after plugin error"));
    expect(
      source,
      contains("final status = await MobileAds.instance.initialize();"),
    );
    expect(source, contains("_safeCanRequestAds()"));
    expect(source, contains("_rewardedLoadCompleter = null;"));
    expect(source, contains("_rewardedInterstitialLoadCompleter = null;"));
  });

  test(
    'internal iOS builds can force test ads without changing production ids',
    () {
      final source = File('lib/services/ads_service.dart').readAsStringSync();

      expect(source, contains("bool.fromEnvironment('INTERNAL_TESTING')"));
      expect(source, contains("bool.fromEnvironment('ADMOB_USE_TEST_ADS')"));
      expect(source, contains("_appEnvironment == 'staging'"));
      expect(
        source,
        contains(
          "return !_useTestAds ? _iosRewardedProductionId : _iosRewardedTestId;",
        ),
      );
      expect(
        source,
        contains(
          "return !_useTestAds\n"
          "        ? _iosRewardedInterstitialProductionId\n"
          "        : _iosRewardedInterstitialTestId;",
        ),
      );
    },
  );

  test('post-game interstitial keeps Android path and adds iOS fallback', () {
    final source = File(
      'lib/services/game_interstitial_service.dart',
    ).readAsStringSync();

    expect(source, contains("ADMOB_ANDROID_INTERSTITIAL_ID"));
    expect(source, contains("return kReleaseMode ? '' : _androidTestId;"));
    expect(source, contains("InterstitialAd.load("));
    expect(
      source,
      contains(
        "_tryIosRewardedInterstitialFallback('missing-interstitial-id')",
      ),
    );
    expect(
      source,
      contains(
        "_tryIosRewardedInterstitialFallback('interstitial-not-loaded')",
      ),
    );
    expect(source, contains("return _ads.showRewardedInterstitial();"));
  });
}
