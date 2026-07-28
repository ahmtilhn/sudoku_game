import 'dart:async';

import 'package:flutter/foundation.dart';

import '../debug/debug_economy.dart';
import 'ads_service.dart';
import 'economy_api_client.dart';

class EconomyService extends ChangeNotifier {
  EconomyService._();

  static final EconomyService instance = EconomyService._();

  WalletSnapshot? wallet;
  bool loading = false;
  bool claimingDaily = false;
  bool showingDailyAd = false;
  bool processingPurchase = false;
  String? error;
  Future<void>? _initialization;

  int get balance => debugUnlimitedCoinsEnabled
      ? debugUnlimitedCoinBalance
      : wallet?.balance ?? 0;
  bool get canEnterOnline =>
      debugUnlimitedCoinsEnabled || (wallet?.canEnterOnline ?? false);
  int get entryFee => wallet?.entryFee ?? 100;
  int get winnerPot => wallet?.winnerPot ?? 200;

  Future<void> initialize() {
    return _initialization ??= refresh().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> refresh({bool showLoading = true}) async {
    if (showLoading) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      wallet = _debugWallet(await EconomyApiClient.instance.loadWallet());
      error = null;
    } on EconomyApiException catch (exception) {
      if (debugUnlimitedCoinsEnabled) {
        wallet = _debugWallet(wallet);
        error = null;
      } else {
        error = exception.message;
      }
    } catch (_) {
      if (debugUnlimitedCoinsEnabled) {
        wallet = _debugWallet(wallet);
        error = null;
      } else {
        error = 'Unable to load your Coin balance.';
      }
    } finally {
      if (showLoading) loading = false;
      notifyListeners();
    }
  }

  Future<bool> claimDailyLogin() async {
    if (claimingDaily || wallet?.dailyLoginAvailable == false) return false;
    claimingDaily = true;
    error = null;
    notifyListeners();
    try {
      wallet = await EconomyApiClient.instance.claimDailyLogin();
      return true;
    } on EconomyApiException catch (exception) {
      error = exception.message;
      return false;
    } catch (_) {
      error = 'The daily reward could not be claimed.';
      return false;
    } finally {
      claimingDaily = false;
      notifyListeners();
    }
  }

  Future<bool> claimDailyRewardedAd() async {
    if (showingDailyAd || wallet?.dailyAdAvailable == false) return false;
    showingDailyAd = true;
    error = null;
    notifyListeners();
    try {
      final prepared = await EconomyApiClient.instance.prepareDailyAd();
      final earned = await AdsService.instance.showRewarded(
        verificationToken: prepared.token,
      );
      if (!earned) return false;
      wallet = await EconomyApiClient.instance.confirmDailyAd(prepared.token);
      return true;
    } on EconomyApiException catch (exception) {
      error = exception.message;
      return false;
    } catch (_) {
      error = 'The rewarded ad is not available right now.';
      return false;
    } finally {
      showingDailyAd = false;
      notifyListeners();
    }
  }

  Future<bool> claimCareerRewardedInterstitial() async {
    try {
      final prepared = await EconomyApiClient.instance.prepareCareerAd();
      final earned = await AdsService.instance.showRewardedInterstitial(
        verificationToken: prepared.token,
      );
      if (!earned) return false;
      wallet = await EconomyApiClient.instance.confirmCareerAd(prepared.token);
      error = null;
      notifyListeners();
      return true;
    } on EconomyApiException catch (exception) {
      error = exception.message;
      notifyListeners();
      return false;
    } catch (_) {
      error = 'The career reward ad is not available right now.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> spendCareerContinue() async {
    if (debugUnlimitedCoinsEnabled) {
      wallet = _debugWallet(wallet);
      error = null;
      notifyListeners();
      return true;
    }
    try {
      wallet = await EconomyApiClient.instance.spendCareerContinue(
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      error = null;
      notifyListeners();
      return true;
    } on EconomyApiException catch (exception) {
      error = exception.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> claimAchievement(String achievementId) async {
    try {
      wallet = await EconomyApiClient.instance.claimAchievement(achievementId);
      error = null;
      notifyListeners();
      return true;
    } on EconomyApiException catch (exception) {
      if (exception.statusCode != 409 && exception.statusCode != 404) {
        error = exception.message;
        notifyListeners();
      }
      return false;
    }
  }

  Future<RematchInvitation> createRematch(String matchId) async {
    final invitation = await EconomyApiClient.instance.createRematch(matchId);
    await refresh(showLoading: false);
    return invitation;
  }

  Future<List<RematchInvitation>> loadRematches() {
    return EconomyApiClient.instance.loadRematches();
  }

  Future<RematchInvitation> respondRematch({
    required String invitationId,
    required bool accept,
  }) async {
    final invitation = await EconomyApiClient.instance.respondRematch(
      invitationId: invitationId,
      accept: accept,
    );
    await refresh(showLoading: false);
    return invitation;
  }

  Future<void> applyPurchaseWallet(WalletSnapshot snapshot) async {
    wallet = snapshot;
    processingPurchase = false;
    error = null;
    notifyListeners();
  }

  void setPurchaseProcessing(bool value) {
    processingPurchase = value;
    notifyListeners();
  }

  void reportError(String message) {
    error = message;
    processingPurchase = false;
    notifyListeners();
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  WalletSnapshot _debugWallet(WalletSnapshot? source) {
    if (!debugUnlimitedCoinsEnabled) {
      return source ??
          const WalletSnapshot(
            balance: 0,
            canEnterOnline: false,
            minimumOnlineBalance: 100,
            entryFee: 100,
            winnerPot: 200,
            starterGrant: 1000,
            dailyLoginAmount: 50,
            dailyLoginAvailable: false,
            dailyAdAmount: 50,
            dailyAdAvailable: false,
          );
    }
    return WalletSnapshot(
      balance: debugUnlimitedCoinBalance,
      canEnterOnline: true,
      minimumOnlineBalance: source?.minimumOnlineBalance ?? 100,
      entryFee: source?.entryFee ?? 100,
      winnerPot: source?.winnerPot ?? 200,
      starterGrant: source?.starterGrant ?? 1000,
      dailyLoginAmount: source?.dailyLoginAmount ?? 50,
      dailyLoginAvailable: source?.dailyLoginAvailable ?? false,
      dailyAdAmount: source?.dailyAdAmount ?? 50,
      dailyAdAvailable: source?.dailyAdAvailable ?? false,
      nextDailyResetAt: source?.nextDailyResetAt,
    );
  }
}
