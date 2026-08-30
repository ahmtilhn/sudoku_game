import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('post-game ads use normal production interstitial units', () {
    final source = File(
      'lib/services/game_interstitial_service.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('ca-app-pub-8422988604275177/4765402169'),
      reason: 'Android release must use the production interstitial unit.',
    );
    expect(
      source,
      contains('ca-app-pub-8422988604275177/3728969311'),
      reason: 'iOS release must use the production interstitial unit.',
    );
    expect(source, contains('InterstitialAd.load('));
    expect(source, contains('FullScreenContentCallback<InterstitialAd>'));
    expect(source, isNot(contains('_tryIosRewardedInterstitialFallback')));
    expect(source, isNot(contains('showRewardedInterstitial(')));
  });

  test('native AdMob application IDs remain production configured', () {
    final androidServices = File(
      'android/app/src/main/res/values/services.xml',
    ).readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      androidServices,
      contains('ca-app-pub-8422988604275177~6950938184'),
    );
    expect(iosInfo, contains('ca-app-pub-8422988604275177~3293784266'));
  });
}
