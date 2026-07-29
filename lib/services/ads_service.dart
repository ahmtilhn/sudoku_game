import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  static const bool _metaSdkEnabled = bool.fromEnvironment(
    'META_SDK_ENABLED',
    defaultValue: false,
  );
  static const bool _metaAdvertiserTrackingEnabled = bool.fromEnvironment(
    'META_ADVERTISER_TRACKING_ENABLED',
    defaultValue: false,
  );

  final FacebookAppEvents _facebookEvents = FacebookAppEvents();
  final ValueNotifier<bool> adsAvailable = ValueNotifier<bool>(false);
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(false);

  RewardedAd? _rewardedAd;
  RewardedInterstitialAd? _rewardedInterstitialAd;
  Completer<void>? _rewardedLoadCompleter;
  Completer<void>? _rewardedInterstitialLoadCompleter;
  bool _initializing = false;
  bool _mobileAdsInitialized = false;
  bool _noAds = false;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get noAds => _noAds;

  void setNoAds(bool value) {
    if (_noAds == value) return;
    _noAds = value;
    if (value) {
      adsAvailable.value = false;
      unawaited(_disposeLoadedAds());
    }
  }

  String get _rewardedAdUnitId {
    if (Platform.isAndroid) {
      return const String.fromEnvironment(
        'ADMOB_ANDROID_REWARDED_ID',
        defaultValue: 'ca-app-pub-3940256099942544/5224354917',
      );
    }
    return const String.fromEnvironment(
      'ADMOB_IOS_REWARDED_ID',
      defaultValue: 'ca-app-pub-3940256099942544/1712485313',
    );
  }

  String get _rewardedInterstitialAdUnitId {
    if (Platform.isAndroid) {
      return const String.fromEnvironment(
        'ADMOB_ANDROID_REWARDED_INTERSTITIAL_ID',
        defaultValue: 'ca-app-pub-3940256099942544/5354046379',
      );
    }
    return const String.fromEnvironment(
      'ADMOB_IOS_REWARDED_INTERSTITIAL_ID',
      defaultValue: 'ca-app-pub-3940256099942544/6978759866',
    );
  }

  Future<void> initialize() async {
    if (_noAds || !_supported || _initializing || _mobileAdsInitialized) return;
    _initializing = true;
    final completed = Completer<void>();

    void finish() {
      if (!completed.isCompleted) completed.complete();
    }

    Future<void> continueAfterConsent() async {
      await _updatePrivacyOptionsRequirement();
      final canRequest = await ConsentInformation.instance.canRequestAds();
      if (!canRequest) {
        adsAvailable.value = false;
        finish();
        return;
      }

      await _requestTrackingAuthorizationIfNeeded();
      await MobileAds.instance.initialize();
      _mobileAdsInitialized = true;
      adsAvailable.value = true;
      await _configureMetaAppEvents();
      unawaited(_loadRewardedAd());
      unawaited(_loadRewardedInterstitialAd());
      finish();
    }

    final parameters = ConsentRequestParameters();
    ConsentInformation.instance.requestConsentInfoUpdate(
      parameters,
      () {
        unawaited(() async {
          await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            if (formError != null) {
              debugPrint('UMP consent form error: ${formError.message}');
            }
          });
          await continueAfterConsent();
        }());
      },
      (error) {
        debugPrint('UMP consent update error: ${error.message}');
        unawaited(continueAfterConsent());
      },
    );

    try {
      await completed.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      debugPrint('Ads initialization timed out. Ads remain unavailable.');
    } finally {
      _initializing = false;
    }
  }

  Future<bool> showRewarded({String? verificationToken}) async {
    if (_noAds || !_supported) return false;
    if (!_mobileAdsInitialized) await initialize();
    if (!adsAvailable.value) return false;

    if (_rewardedAd == null) await _loadRewardedAd();
    final ad = _rewardedAd;
    if (ad == null) return false;

    _rewardedAd = null;
    await _setServerSideOptions(ad, verificationToken);
    final result = Completer<bool>();
    var earnedReward = false;

    void complete(bool value) {
      if (!result.isCompleted) result.complete(value);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        debugPrint('Rewarded ad failed to show: $error');
        failedAd.dispose();
        complete(false);
        unawaited(_loadRewardedAd());
      },
      onAdDismissedFullScreenContent: (dismissedAd) {
        dismissedAd.dispose();
        complete(earnedReward);
        unawaited(_loadRewardedAd());
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (shownAd, reward) {
          earnedReward = true;
        },
      );
    } catch (error) {
      debugPrint('Rewarded ad show threw: $error');
      await ad.dispose();
      unawaited(_loadRewardedAd());
      return false;
    }

    try {
      return await result.future.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      await ad.dispose();
      return false;
    }
  }

  Future<bool> showRewardedInterstitial({String? verificationToken}) async {
    if (_noAds || !_supported) return false;
    if (!_mobileAdsInitialized) await initialize();
    if (!adsAvailable.value) return false;

    if (_rewardedInterstitialAd == null) {
      await _loadRewardedInterstitialAd();
    }
    final ad = _rewardedInterstitialAd;
    if (ad == null) return false;

    _rewardedInterstitialAd = null;
    await _setServerSideOptions(ad, verificationToken);
    final result = Completer<bool>();
    var earnedReward = false;

    void complete(bool value) {
      if (!result.isCompleted) result.complete(value);
    }

    ad.fullScreenContentCallback =
        FullScreenContentCallback<RewardedInterstitialAd>(
          onAdFailedToShowFullScreenContent: (failedAd, error) {
            debugPrint('Rewarded interstitial failed to show: $error');
            failedAd.dispose();
            complete(false);
            unawaited(_loadRewardedInterstitialAd());
          },
          onAdDismissedFullScreenContent: (dismissedAd) {
            dismissedAd.dispose();
            complete(earnedReward);
            unawaited(_loadRewardedInterstitialAd());
          },
        );

    try {
      await ad.show(
        onUserEarnedReward: (shownAd, reward) {
          earnedReward = true;
        },
      );
    } catch (error) {
      debugPrint('Rewarded interstitial show threw: $error');
      await ad.dispose();
      unawaited(_loadRewardedInterstitialAd());
      return false;
    }

    try {
      return await result.future.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      await ad.dispose();
      return false;
    }
  }

  Future<void> showPrivacyOptions() async {
    if (_noAds || !_supported) return;
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) {
        debugPrint('UMP privacy options error: ${error.message}');
      }
    });
    await _updatePrivacyOptionsRequirement();
  }

  Future<void> _setServerSideOptions(
    Object ad,
    String? verificationToken,
  ) async {
    final token = verificationToken?.trim();
    if (token == null || token.isEmpty) return;
    final options = ServerSideVerificationOptions(customData: token);
    if (ad is RewardedAd) {
      await ad.setServerSideOptions(options);
    } else if (ad is RewardedInterstitialAd) {
      await ad.setServerSideOptions(options);
    }
  }

  Future<void> _loadRewardedAd() async {
    if (_noAds ||
        !_supported ||
        !_mobileAdsInitialized ||
        !adsAvailable.value) {
      return;
    }
    if (_rewardedAd != null) return;

    final existing = _rewardedLoadCompleter;
    if (existing != null) {
      await existing.future;
      return;
    }

    final completer = Completer<void>();
    _rewardedLoadCompleter = completer;

    await RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (_noAds) {
            ad.dispose();
            if (!completer.isCompleted) completer.complete();
            return;
          }
          _rewardedAd = ad;
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed to load: $error');
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('Rewarded ad load timed out.');
    } finally {
      if (identical(_rewardedLoadCompleter, completer)) {
        _rewardedLoadCompleter = null;
      }
    }
  }

  Future<void> _loadRewardedInterstitialAd() async {
    if (_noAds ||
        !_supported ||
        !_mobileAdsInitialized ||
        !adsAvailable.value) {
      return;
    }
    if (_rewardedInterstitialAd != null) return;

    final existing = _rewardedInterstitialLoadCompleter;
    if (existing != null) {
      await existing.future;
      return;
    }

    final completer = Completer<void>();
    _rewardedInterstitialLoadCompleter = completer;

    await RewardedInterstitialAd.load(
      adUnitId: _rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (_noAds) {
            ad.dispose();
            if (!completer.isCompleted) completer.complete();
            return;
          }
          _rewardedInterstitialAd = ad;
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded interstitial failed to load: $error');
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('Rewarded interstitial load timed out.');
    } finally {
      if (identical(_rewardedInterstitialLoadCompleter, completer)) {
        _rewardedInterstitialLoadCompleter = null;
      }
    }
  }

  Future<void> _updatePrivacyOptionsRequirement() async {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    privacyOptionsRequired.value =
        status == PrivacyOptionsRequirementStatus.required;
  }

  Future<void> _requestTrackingAuthorizationIfNeeded() async {
    if (!Platform.isIOS) return;
    final current = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (current == TrackingStatus.notDetermined) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }

  Future<void> _configureMetaAppEvents() async {
    if (!_metaSdkEnabled) return;

    await _facebookEvents.setAutoLogAppEventsEnabled(true);
    await _facebookEvents.setAdvertiserIdCollectionEnabled(
      _metaAdvertiserTrackingEnabled,
    );
    await _facebookEvents.activateApp();
  }

  Future<void> _disposeLoadedAds() async {
    final rewarded = _rewardedAd;
    final interstitial = _rewardedInterstitialAd;
    _rewardedAd = null;
    _rewardedInterstitialAd = null;
    await rewarded?.dispose();
    await interstitial?.dispose();
  }
}
