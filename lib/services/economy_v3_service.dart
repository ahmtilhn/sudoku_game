import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ads_service.dart';
import 'economy_api_client.dart';
import 'economy_service.dart';
import 'economy_v3_api_client.dart';

class EconomyV3Service extends ChangeNotifier {
  EconomyV3Service._();

  static final EconomyV3Service instance = EconomyV3Service._();

  final EconomyV3ApiClient _api = EconomyV3ApiClient.instance;
  final AdsService _ads = AdsService.instance;

  EconomyV3State? _state;
  String? _error;
  String? _errorCode;
  bool _loading = false;

  EconomyV3State? get state => _state;
  String? get error => _error;
  String? get errorCode => _errorCode;
  bool get loading => _loading;

  Future<void> initialize() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _state = await _api.loadState();
      await _syncLegacyWallet();
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => initialize();

  Future<EconomyV3ClaimResult?> claimDailyIfAvailable() async {
    try {
      final current = _state ?? await _api.loadState();
      _state = current;
      if (!current.dailyAvailable) {
        notifyListeners();
        return null;
      }
      final result = await _api.claimDaily();
      _state = result.state;
      _error = null;
      await _syncLegacyWallet();
      notifyListeners();
      return result;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<EconomyV3ClaimResult?> doubleLastDailyReward() async {
    if (_ads.noAds) return null;
    try {
      final preparation = await _api.prepareDailyDouble();
      if (preparation.token.isEmpty) return null;
      final earned = await _ads.showRewarded(
        verificationToken: preparation.token,
      );
      if (!earned) return null;
      final result = await _confirmAfterSsv(
        () => _api.confirmDailyDouble(preparation.token),
      );
      _state = result.state;
      _error = null;
      await _syncLegacyWallet();
      notifyListeners();
      return result;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<EconomyV3ClaimResult?> claimCareer({
    required int level,
    required String variant,
  }) async {
    try {
      final result = await _api.claimCareer(level: level, variant: variant);
      _state = result.state;
      _error = null;
      _errorCode = null;
      await _syncLegacyWallet();
      notifyListeners();
      return result;
    } on EconomyApiException catch (error) {
      _error = error.toString();
      _errorCode = error.code;
      notifyListeners();
      return null;
    } catch (error) {
      _error = error.toString();
      _errorCode = null;
      notifyListeners();
      return null;
    }
  }

  Future<EconomyV3ClaimResult?> doubleCareerReward({
    required int level,
    required String variant,
  }) async {
    if (_ads.noAds) return null;
    try {
      final preparation = await _api.prepareCareerDouble(
        level: level,
        variant: variant,
      );
      if (preparation.token.isEmpty || preparation.amount <= 0) return null;
      final earned = await _ads.showRewarded(
        verificationToken: preparation.token,
      );
      if (!earned) return null;
      final result = await _confirmAfterSsv(
        () => _api.confirmCareerDouble(preparation.token),
      );
      _state = result.state;
      _error = null;
      _errorCode = null;
      await _syncLegacyWallet();
      notifyListeners();
      return result;
    } on EconomyApiException catch (error) {
      _error = error.toString();
      _errorCode = error.code;
      notifyListeners();
      return null;
    } catch (error) {
      _error = error.toString();
      _errorCode = null;
      notifyListeners();
      return null;
    }
  }

  Future<bool> purchaseHint({required String requestId}) async {
    try {
      final result = await _api.purchaseHint(requestId);
      _state = result.state;
      _error = null;
      await _syncLegacyWallet();
      notifyListeners();
      return result.granted;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> earnHintWithAd() => _earnHintWithAd(
    showAd: (token) => _ads.showRewarded(verificationToken: token),
  );

  Future<bool> earnHintWithRewardedInterstitial() => _earnHintWithAd(
    showAd: (token) =>
        _ads.showRewardedInterstitial(verificationToken: token),
  );

  Future<bool> _earnHintWithAd({
    required Future<bool> Function(String token) showAd,
  }) async {
    if (_ads.noAds) return false;
    try {
      final preparation = await _api.prepareHintReward();
      if (preparation.token.isEmpty) return false;
      final earned = await showAd(preparation.token);
      if (!earned) return false;
      final result = await _confirmAfterSsv(
        () => _api.confirmHintReward(preparation.token),
      );
      _state = result.state;
      _error = null;
      await _syncLegacyWallet();
      notifyListeners();
      return result.granted;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<int> consumeHintRefill() async {
    try {
      final result = await _api.consumeHintRefill();
      _state = result.state;
      _error = null;
      notifyListeners();
      return result.granted ? (_state?.hintRefillSize ?? 3) : 0;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return 0;
    }
  }

  Future<EconomyV3RecoveryOffer?> prepareRecovery(String matchId) async {
    try {
      final offer = await _api.prepareRecovery(matchId);
      _error = null;
      notifyListeners();
      return offer;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<EconomyV3ClaimResult?> claimRecovery(
    EconomyV3RecoveryOffer offer,
  ) async {
    if (_ads.noAds || !offer.eligible) return null;
    final token = offer.token;
    if (token == null || token.isEmpty) return null;
    try {
      final earned = await _ads.showRewarded(verificationToken: token);
      if (!earned) return null;
      final result = await _confirmAfterSsv(
        () => _api.confirmRecovery(token),
      );
      _state = result.state;
      _error = null;
      await _syncLegacyWallet();
      notifyListeners();
      return result;
    } catch (error) {
      _error = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> dismissRecovery(String matchId) async {
    try {
      await _api.dismissRecovery(matchId);
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<EconomyV3ClaimResult> _confirmAfterSsv(
    Future<EconomyV3ClaimResult> Function() confirm,
  ) async {
    const attempts = 8;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await confirm();
      } on EconomyApiException catch (error) {
        final waiting = error.code == 'reward_waiting_for_ssv';
        if (!waiting || attempt == attempts - 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw StateError('Reward confirmation retry exhausted.');
  }

  Future<void> _syncLegacyWallet() async {
    try {
      await EconomyService.instance.refresh();
    } catch (_) {
      // V3 state remains authoritative for rewards if legacy wallet refresh fails.
    }
  }
}
