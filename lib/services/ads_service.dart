import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  static const String _androidRewardedProductionId =
      'ca-app-pub-8422988604275177/3474727600';
  static const String _androidRewardedInterstitialProductionId =
      'ca-app-pub-8422988604275177/4787809275';
  static const String _iosRewardedProductionId =
      'ca-app-pub-8422988604275177/3366916396';
  static const String _iosRewardedInterstitialProductionId =
      'ca-app-pub-8422988604275177/4982984468';

  static const String _appEnvironment = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: '',
  );
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

  String get _rewardedAdUnitId => Platform.isAndroid
      ? _androidRewardedProductionId
      : _iosRewardedProductionId;

  String get _rewardedInterstitialAdUnitId => Platform.isAndroid
      ? _androidRewardedInterstitialProductionId
      : _iosRewardedInterstitialProductionId;

  Future<void> initialize() async {
    if (_noAds || !_supported || _initializing || _mobileAdsInitialized) {
      _logInitializationSkipped();
      return;
    }
    _initializing = true;
    final completed = Completer<void>();
    debugPrint(
      'Ads initialization starting: platform=$_platformForLog, '
      'release=$kReleaseMode, environment=$_appEnvironmentOrDefault, '
      'productionUnits=true, rewarded=${_unitForLog(_rewardedAdUnitId)}, '
      'rewardedInterstitial=${_unitForLog(_rewardedInterstitialAdUnitId)}.',
    );

    void finish() {
      if (!completed.isCompleted) completed.complete();
    }

    Future<void> continueAfterConsent() async {
      final consentStatus = await _safeConsentStatus();
      await _updatePrivacyOptionsRequirement();
      final canRequest = await _safeCanRequestAds();
      debugPrint(
        'Ads consent resolved: platform=$_platformForLog, '
        'status=$consentStatus, canRequestAds=$canRequest, '
        'privacyOptionsRequired=${privacyOptionsRequired.value}.',
      );
      if (!canRequest) {
        adsAvailable.value = false;
        finish();
        return;
      }

      await _requestTrackingAuthorizationIfNeeded();
      final status = await MobileAds.instance.initialize();
      _mobileAdsInitialized = true;
      adsAvailable.value = true;
      debugPrint(
        'Ads SDK initialized: platform=$_platformForLog, '
        'adapters=${_adapterStatusSummary(status)}.',
      );
      unawaited(_loadRewardedAd());
      unawaited(_loadRewardedInterstitialAd());
      finish();
    }

    final parameters = ConsentRequestParameters();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        parameters,
        () {
          unawaited(() async {
            try {
              await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
                if (formError != null) {
                  debugPrint('UMP consent form error: ${formError.message}');
                }
              });
              await continueAfterConsent();
            } catch (error, stackTrace) {
              debugPrint('Ads consent flow failed: $error');
              debugPrintStack(stackTrace: stackTrace);
              finish();
            }
          }());
        },
        (error) {
          debugPrint('UMP consent update error: ${error.message}');
          unawaited(() async {
            try {
              await continueAfterConsent();
            } catch (innerError, stackTrace) {
              debugPrint('Ads fallback consent flow failed: $innerError');
              debugPrintStack(stackTrace: stackTrace);
              finish();
            }
          }());
        },
      );
    } catch (error, stackTrace) {
      debugPrint('UMP consent update threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      finish();
    }

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
    if (ad == null) {
      if (Platform.isIOS) {
        debugPrint(
          'Rewarded ad unavailable on iOS; trying rewarded interstitial '
          'fallback.',
        );
        return showRewardedInterstitial(verificationToken: verificationToken);
      }
      debugPrint('Rewarded ad unavailable after load attempt.');
      return false;
    }

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
    if (ad == null) {
      debugPrint('Rewarded interstitial unavailable after load attempt.');
      return false;
    }

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

    try {
      debugPrint(
        'Rewarded ad loading: unit=${_unitForLog(_rewardedAdUnitId)}.',
      );
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
            debugPrint(
              'Rewarded ad loaded: unit=${_unitForLog(ad.adUnitId)}, '
              'response=${_responseInfoForLog(ad.responseInfo)}.',
            );
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              'Rewarded ad failed to load: '
              '${_loadErrorForLog(error)}.',
            );
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('Rewarded ad load timed out.');
    } catch (error, stackTrace) {
      debugPrint('Rewarded ad load threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!completer.isCompleted) completer.complete();
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

    try {
      debugPrint(
        'Rewarded interstitial loading: '
        'unit=${_unitForLog(_rewardedInterstitialAdUnitId)}.',
      );
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
            debugPrint(
              'Rewarded interstitial loaded: '
              'unit=${_unitForLog(ad.adUnitId)}, '
              'response=${_responseInfoForLog(ad.responseInfo)}.',
            );
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              'Rewarded interstitial failed to load: '
              '${_loadErrorForLog(error)}.',
            );
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );
      await completer.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('Rewarded interstitial load timed out.');
    } catch (error, stackTrace) {
      debugPrint('Rewarded interstitial load threw: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!completer.isCompleted) completer.complete();
    } finally {
      if (identical(_rewardedInterstitialLoadCompleter, completer)) {
        _rewardedInterstitialLoadCompleter = null;
      }
    }
  }

  Future<void> _updatePrivacyOptionsRequirement() async {
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      privacyOptionsRequired.value =
          status == PrivacyOptionsRequirementStatus.required;
    } catch (error, stackTrace) {
      debugPrint('UMP privacy requirement lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      privacyOptionsRequired.value = false;
    }
  }

  Future<void> _requestTrackingAuthorizationIfNeeded() async {
    if (!Platform.isIOS) return;
    try {
      final current = await AppTrackingTransparency.trackingAuthorizationStatus;
      debugPrint('ATT status before ads: $current.');
      if (current == TrackingStatus.notDetermined) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated =
            await AppTrackingTransparency.requestTrackingAuthorization();
        debugPrint('ATT status after request: $updated.');
      }
    } catch (error, stackTrace) {
      debugPrint('ATT request skipped after plugin error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _disposeLoadedAds() async {
    final rewarded = _rewardedAd;
    final interstitial = _rewardedInterstitialAd;
    _rewardedAd = null;
    _rewardedInterstitialAd = null;
    await rewarded?.dispose();
    await interstitial?.dispose();
  }

  Future<ConsentStatus> _safeConsentStatus() async {
    try {
      return await ConsentInformation.instance.getConsentStatus();
    } catch (error, stackTrace) {
      debugPrint('UMP consent status lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return ConsentStatus.unknown;
    }
  }

  Future<bool> _safeCanRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (error, stackTrace) {
      debugPrint('UMP canRequestAds lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  void _logInitializationSkipped() {
    if (!_supported) {
      debugPrint('Ads initialization skipped: unsupported platform.');
    } else if (_noAds) {
      debugPrint('Ads initialization skipped: no-ads entitlement active.');
    } else if (_initializing) {
      debugPrint('Ads initialization skipped: already initializing.');
    } else if (_mobileAdsInitialized) {
      debugPrint('Ads initialization skipped: SDK already initialized.');
    }
  }

  String get _platformForLog {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  String get _appEnvironmentOrDefault => _appEnvironment.isEmpty
      ? (kReleaseMode ? 'release' : 'debug')
      : _appEnvironment;

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

  String _adapterStatusSummary(InitializationStatus status) {
    if (status.adapterStatuses.isEmpty) return 'none';
    return status.adapterStatuses.entries
        .map(
          (entry) =>
              '${entry.key}:${entry.value.state.name}/${entry.value.description}',
        )
        .join(', ');
  }
}
