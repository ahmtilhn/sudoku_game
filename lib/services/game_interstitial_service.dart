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

  static const String _androidProductionId =
      'ca-app-pub-8422988604275177/4765402169';
  static const String _iosProductionId =
      'ca-app-pub-8422988604275177/3728969311';
  static const String _androidTestId = 'ca-app-pub-3940256099942544/1033173712';
  static const String _iosTestId = 'ca-app-pub-3940256099942544/4411468910';

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
      return kReleaseMode ? _androidProductionId : _androidTestId;
    }
    const configured = String.fromEnvironment(
      'ADMOB_IOS_INTERSTITIAL_ID',
      defaultValue: '',
    );
    if (configured.isNotEmpty) return configured;
    return kReleaseMode ? _iosProductionId : _iosTestId;
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
    try {
      debugPrint(
        'Post-game interstitial loading: unit=${_unitForLog(_adUnitId)}.',
      );
      await InterstitialAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (_ads.noAds) {
              ad.dispose();
            } else {
              _loadedAd = ad;
            }
            debugPrint(
              'Post-game interstitial loaded: unit=${_unitForLog(ad.adUnitId)}, '
              'response=${_responseInfoForLog(ad.responseInfo)}.',
            );
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              'Post-game interstitial failed to load: '
              '${_loadErrorForLog(error)}.',
            );
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('Post-game interstitial load timed out.');
    } catch (error, stackTrace) {
      debugPrint('Post-game interstitial load threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!completer.isCompleted) completer.complete();
    } finally {
      if (identical(_loadCompleter, completer)) _loadCompleter = null;
    }
  }

  String _unitForLog(String adUnitId) {
    final value = adUnitId.trim();
    if (value.isEmpty) return 'empty';
    final type = value.contains('3940256099942544') ? 'test' : 'production';
    final slash = value.lastIndexOf('/');
    final tail = slash == -1 ? value : value.substring(slash + 1);
    final compactTail = tail.length <= 4
        ? tail
        : tail.substring(tail.length - 4);
    return '$type:...$compactTail';
  }

  String _loadErrorForLog(LoadAdError error) {
    return 'code=${error.code}, domain=${error.domain}, '
        'message=${error.message}, '
        'response=${_responseInfoForLog(error.responseInfo)}';
  }

  String _responseInfoForLog(ResponseInfo? info) {
    if (info == null) return 'none';
    return 'responseId=${info.responseId ?? 'none'}, '
        'adapter=${info.mediationAdapterClassName ?? 'none'}, '
        'loadedAdapter=${info.loadedAdapterResponseInfo?.adapterClassName ?? 'none'}, '
        'adapterCount=${info.adapterResponses?.length ?? 0}';
  }
}
