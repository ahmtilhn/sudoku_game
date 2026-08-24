import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../debug/debug_economy.dart';
import 'ads_service.dart';
import 'economy_api_client.dart';
import 'economy_v3_api_client.dart';

int positiveCoinDelta(int before, int after) =>
    after > before ? after - before : 0;

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
  bool _notificationQueued = false;

  int get balance => debugUnlimitedCoinsEnabled
      ? debugUnlimitedCoinBalance
      : wallet?.balance ?? 0;
  bool get canEnterOnline =>
      debugUnlimitedCoinsEnabled || (wallet?.canEnterOnline ?? false);
  int get entryFee => wallet?.entryFee ?? 100;
  int get winnerPot => wallet?.winnerPot ?? 200;
  int get minimumOnlineBalance => wallet?.minimumOnlineBalance ?? 100;
  bool get noAds => wallet?.noAds ?? false;

  int entryFeeForDifficulty(String difficulty) {
    return wallet?.entryFeeForDifficulty(difficulty) ??
        const <String, int>{
          'beginner': 100,
          'easy': 150,
          'medium': 250,
          'hard': 400,
          'expert': 650,
        }[difficulty.toLowerCase()] ??
        100;
  }

  int winnerPotForDifficulty(String difficulty) {
    return entryFeeForDifficulty(difficulty) * 2;
  }

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
      _syncAdEntitlement();
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

  /// Compatibility bridge for older screens. The flat +50 daily-login reward
  /// no longer exists; this now claims the next Economy V3 calendar entry.
  Future<bool> claimDailyLogin() async {
    if (claimingDaily) return false;
    claimingDaily = true;
    error = null;
    notifyListeners();
    try {
      final result = await EconomyV3ApiClient.instance.claimDaily();
      await refresh(showLoading: false);
      return result.granted;
    } on EconomyApiException catch (exception) {
      if (exception.code == 'already_claimed_today') return false;
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

  /// Compatibility bridge for older screens. The old flat +50 daily ad has
  /// become a one-time double of the current day's Coin calendar reward.
  Future<bool> claimDailyRewardedAd() async {
    if (noAds || showingDailyAd) return false;
    showingDailyAd = true;
    error = null;
    notifyListeners();
    try {
      final prepared = await EconomyV3ApiClient.instance.prepareDailyDouble();
      final earned = await AdsService.instance.showRewarded(
        verificationToken: prepared.token,
      );
      if (!earned) return false;
      final result = await _confirmRewardAfterSsv(
        () => EconomyV3ApiClient.instance.confirmDailyDouble(prepared.token),
      );
      await refresh(showLoading: false);
      _syncAdEntitlement();
      return result.granted;
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

  /// Economy V3 intentionally removed the generic repeatable +25 Career ad.
  /// Keeping this method as a no-op avoids breaking older result widgets while
  /// guaranteeing they cannot mint Coins through the retired flow.
  Future<int> claimCareerRewardedInterstitialCoins() async => 0;

  Future<bool> claimCareerRewardedInterstitial() async => false;

  Future<EconomyV3ClaimResult> _confirmRewardAfterSsv(
    Future<EconomyV3ClaimResult> Function() confirm,
  ) async {
    const attempts = 8;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await confirm();
      } on EconomyApiException catch (exception) {
        final waiting = exception.code == 'reward_waiting_for_ssv';
        if (!waiting || attempt == attempts - 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw StateError('Reward confirmation retry exhausted.');
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
      _syncAdEntitlement();
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
      _syncAdEntitlement();
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
    // Challenge Again is idempotent for one finished match. If our own invite
    // is already pending, return it instead of creating duplicate pushes. If
    // the opponent already asked for a rematch, pressing Challenge Again means
    // the intent is mutual, so accept that invitation immediately.
    try {
      final existing = await EconomyApiClient.instance.loadRematches();
      final now = DateTime.now();
      RematchInvitation? pending;
      for (final invitation in existing) {
        if (invitation.previousMatchId == matchId &&
            invitation.status == 'pending' &&
            invitation.expiresAt.isAfter(now)) {
          pending = invitation;
          break;
        }
      }
      if (pending != null) {
        if (pending.isSender) return pending;
        try {
          final accepted = await EconomyApiClient.instance.respondRematch(
            invitationId: pending.id,
            accept: true,
          );
          await refresh(showLoading: false);
          return accepted;
        } on EconomyApiException catch (exception) {
          if (exception.code != 'rematch_expired' &&
              exception.code != 'rematch_closed') {
            rethrow;
          }
          // It expired between the list and accept calls; create a fresh invite.
        }
      }
    } on EconomyApiException catch (exception) {
      if (exception.statusCode == 401 || exception.statusCode == 403) rethrow;
      // A stale pending-list read must not prevent the explicit rematch request.
    } catch (_) {
      // Continue with the explicit create request below.
    }

    EconomyApiException? settlementError;
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final invitation = await EconomyApiClient.instance.createRematch(
          matchId,
        );
        await refresh(showLoading: false);
        return invitation;
      } on EconomyApiException catch (exception) {
        final waitingForMatchSettlement =
            exception.statusCode == 409 &&
            exception.message.toLowerCase().contains(
              'match has not finished yet',
            );
        if (!waitingForMatchSettlement || attempt == 7) rethrow;
        settlementError = exception;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    throw settlementError ??
        const EconomyApiException(409, 'The match has not finished yet.');
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
    _syncAdEntitlement();
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

  @override
  void notifyListeners() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (_notificationQueued) return;
      _notificationQueued = true;
      binding.addPostFrameCallback((_) {
        _notificationQueued = false;
        _dispatchNotification();
      });
      return;
    }
    _dispatchNotification();
  }

  void _dispatchNotification() {
    super.notifyListeners();
  }

  WalletSnapshot _debugWallet(WalletSnapshot? source) {
    if (!debugUnlimitedCoinsEnabled) {
      return source ??
          const WalletSnapshot(
            balance: 0,
            canEnterOnline: false,
            minimumOnlineBalance: 100,
            entryFees: <String, int>{
              'beginner': 100,
              'easy': 150,
              'medium': 250,
              'hard': 400,
              'expert': 650,
            },
            noAds: false,
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
      entryFees:
          source?.entryFees ??
          const <String, int>{
            'beginner': 100,
            'easy': 150,
            'medium': 250,
            'hard': 400,
            'expert': 650,
          },
      noAds: source?.noAds ?? false,
      starterGrant: source?.starterGrant ?? 1000,
      dailyLoginAmount: source?.dailyLoginAmount ?? 50,
      dailyLoginAvailable: source?.dailyLoginAvailable ?? false,
      dailyAdAmount: source?.dailyAdAmount ?? 50,
      dailyAdAvailable: source?.dailyAdAvailable ?? false,
      nextDailyResetAt: source?.nextDailyResetAt,
    );
  }

  void _syncAdEntitlement() {
    AdsService.instance.setNoAds(noAds);
  }
}
