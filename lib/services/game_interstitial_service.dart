import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_service.dart';
import 'career_reward_sync_service.dart';
import 'economy_service.dart';

enum GameInterstitialContext { careerWin, careerLoss, practice, normalPlay }

/// Central gate for forced, non-rewarded post-result interstitials.
///
/// Every eligible offline result attempts to show an interstitial. Online Duel
/// never calls this service. No Ads entitlement remains the only product-level
/// suppression rule.
class GameInterstitialService {
  GameInterstitialService._();

  static final GameInterstitialService instance = GameInterstitialService._();

  static const String _androidTestId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _iosTestId =
      'ca-app-pub-3940256099942544/4411468910';

  final AdsService _ads = AdsService.instance;

  InterstitialAd? _loadedAd;
  Completer<void>? _loadCompleter;
  bool _showing = false;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  String get _adUnitId {
    if (Platform.isAndroid) {
      const configured = String.fromEnvironment(
        'ADMOB_ANDROID_INTERSTITIAL_ID',
        defaultValue: '',
      );
      if (configured.isNotEmpty) return configured;
      return kReleaseMode ? '' : _androidTestId;
    }
    const configured = String.fromEnvironment(
      'ADMOB_IOS_INTERSTITIAL_ID',
      defaultValue: '',
    );
    if (configured.isNotEmpty) return configured;
    return kReleaseMode ? '' : _iosTestId;
  }

  Future<bool> recordAndMaybeShow(GameInterstitialContext context) async {
    // Career progress is written locally first. Drain the V3 reward sync before
    // reading the result balance, independently from whether an ad can load.
    if (context == GameInterstitialContext.careerWin) {
      await CareerRewardSyncService.instance.waitForIdle();
      await EconomyService.instance.refresh(showLoading: false);
    }

    if (_ads.noAds || !_supported || _showing) return false;
    if (!AdsService.instance.adsAvailable.value) {
      await AdsService.instance.initialize();
    }
    if (_ads.noAds || !AdsService.instance.adsAvailable.value) return false;
    if (_adUnitId.isEmpty) {
      debugPrint(
        'Post-game interstitial is not configured for this release build. '
        'Set ADMOB_ANDROID_INTERSTITIAL_ID / ADMOB_IOS_INTERSTITIAL_ID.',
      );
      return false;
    }

    if (_loadedAd == null) await _load();
    final ad = _loadedAd;
    if (ad == null || _ads.noAds) return false;
    _loadedAd = null;
    _showing = true;

    final completion = Completer<bool>();
    void complete(bool value) {
      if (!completion.isCompleted) completion.complete(value);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        debugPrint('Post-game interstitial failed to show: $error');
        failedAd.dispose();
        complete(false);
      },
      onAdDismissedFullScreenContent: (dismissedAd) {
        dismissedAd.dispose();
        complete(true);
      },
    );

    try {
      ad.show();
      return await completion.future.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      await ad.dispose();
      return false;
    } catch (error) {
      debugPrint('Post-game interstitial show threw: $error');
      await ad.dispose();
      return false;
    } finally {
      _showing = false;
      unawaited(_load());
    }
  }

  Future<void> disposeLoadedAd() async {
    final ad = _loadedAd;
    _loadedAd = null;
    await ad?.dispose();
  }

  Future<void> _load() async {
    if (_ads.noAds ||
        !_supported ||
        !AdsService.instance.adsAvailable.value ||
        _adUnitId.isEmpty ||
        _loadedAd != null) {
      return;
    }
    final current = _loadCompleter;
    if (current != null) {
      await current.future;
      return;
    }

    final completer = Completer<void>();
    _loadCompleter = completer;
    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (_ads.noAds) {
            ad.dispose();
          } else {
            _loadedAd = ad;
          }
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Post-game interstitial failed to load: $error');
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('Post-game interstitial load timed out.');
    } finally {
      if (identical(_loadCompleter, completer)) _loadCompleter = null;
    }
  }
}
