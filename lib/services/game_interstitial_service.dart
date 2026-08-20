import 'package:flutter/material.dart';

import '../core/app_navigator.dart';
import '../data/local_progress_store.dart';
import '../domain/sudoku.dart';
import '../domain/sudoku_variant.dart';
import '../localization/app_strings.dart';
import 'ads_service.dart';
import 'career_reward_sync_service.dart';
import 'economy_service.dart';
import 'economy_v3_service.dart';

enum GameInterstitialContext { careerWin, careerLoss, practice, normalPlay }

/// Central gate for post-game rewarded ads in offline play.
///
/// Every eligible completed offline game gets the rewarded-interstitial offer;
/// there is no frequency counter or cooldown. The required pre-ad disclosure
/// includes a skip action and clearly states the +1 Hint reward.
///
/// When the completion also produced a new server-authoritative Career Coin
/// reward, a separate optional RewardedAd can double that exact reward once.
class GameInterstitialService {
  GameInterstitialService._();

  static final GameInterstitialService instance = GameInterstitialService._();

  final AdsService _ads = AdsService.instance;
  final EconomyV3Service _economyV3 = EconomyV3Service.instance;
  final Map<String, LevelProgress?> _samuraiProgress =
      <String, LevelProgress?>{};
  final Map<SudokuVariantId, int> _careerNextLevel =
      <SudokuVariantId, int>{};
  LocalProgressStore? _store;
  bool _showing = false;
  int _pendingCompletionVersion = 0;

  void bindStore(LocalProgressStore store) {
    if (identical(_store, store)) return;
    _store?.removeListener(_onStoreChanged);
    _store = store;
    _samuraiProgress.clear();
    _careerNextLevel.clear();
    for (final difficulty in SudokuDifficulty.values) {
      final id = 'practice-samurai-${difficulty.name}';
      _samuraiProgress[id] = store.progressFor(id);
    }
    for (final variant in SudokuVariant.values) {
      _careerNextLevel[variant.id] = store.nextCareerLevelNumberFor(variant);
    }
    store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    final store = _store;
    if (store == null) return;

    GameInterstitialContext? detectedCompletion;
    for (final variant in SudokuVariant.values) {
      final previous = _careerNextLevel[variant.id] ?? 1;
      final current = store.nextCareerLevelNumberFor(variant);
      _careerNextLevel[variant.id] = current;
      if (current > previous) {
        CareerRewardSyncService.instance.armRewardCapture();
        detectedCompletion = GameInterstitialContext.careerWin;
      }
    }

    for (final difficulty in SudokuDifficulty.values) {
      final id = 'practice-samurai-${difficulty.name}';
      final previous = _samuraiProgress[id];
      final current = store.progressFor(id);
      if (identical(previous, current)) continue;
      _samuraiProgress[id] = current;
      if (current != null && detectedCompletion == null) {
        detectedCompletion = GameInterstitialContext.practice;
      }
    }

    if (detectedCompletion != null) {
      _scheduleDetectedCompletion(detectedCompletion);
    }
  }

  void _scheduleDetectedCompletion(GameInterstitialContext adContext) {
    final version = ++_pendingCompletionVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (version != _pendingCompletionVersion) return;
      recordAndMaybeShow(adContext, cancelDetectedCompletion: false);
    });
  }

  Future<bool> recordAndMaybeShow(
    GameInterstitialContext adContext, {
    bool cancelDetectedCompletion = true,
  }) async {
    // EnhancedGameScreen calls this directly after its onCompleted callback.
    // Cancel the store-listener fallback so a Career completion cannot surface
    // the same ad flow twice. Legacy Career/Samurai screens use the fallback.
    if (cancelDetectedCompletion) _pendingCompletionVersion++;

    CareerRewardGrant? careerGrant;
    if (adContext == GameInterstitialContext.careerWin) {
      await CareerRewardSyncService.instance.waitForIdle();
      await EconomyService.instance.refresh(showLoading: false);
      // EnhancedGameScreen historically labels all of its completions as
      // careerWin. A fresh grant exists only when Career actually minted Coins,
      // so Practice/Daily completions cannot accidentally receive Career x2.
      careerGrant = CareerRewardSyncService.instance.takeRecentGrant();
    }

    final store = _store;
    final context = AppNavigator.key.currentState?.overlay?.context;
    if (_ads.noAds || _showing || store == null || context == null) return false;
    if (!_ads.adsAvailable.value) await _ads.initialize();
    if (_ads.noAds || !_ads.adsAvailable.value || !context.mounted) return false;

    _showing = true;
    try {
      final earnedPostGameHint = await _offerRewardedInterstitial(
        context: context,
        store: store,
      );

      if (careerGrant != null && context.mounted && !_ads.noAds) {
        await _offerCareerDouble(context, careerGrant);
      }
      return earnedPostGameHint;
    } finally {
      _showing = false;
    }
  }

  Future<bool> _offerRewardedInterstitial({
    required BuildContext context,
    required LocalProgressStore store,
  }) async {
    final watch = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => Padding(
        key: const ValueKey<String>('post-game-rewarded-interstitial-offer'),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.ondemand_video_rounded, size: 46),
            const SizedBox(height: 10),
            Text(
              sheetContext.tr('watch_rewarded_ad'),
              textAlign: TextAlign.center,
              style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '+1 ${sheetContext.tr('hints')}',
              textAlign: TextAlign.center,
              style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: Text(
                '${sheetContext.tr('watch_rewarded_ad')} · +1 ${sheetContext.tr('hints')}',
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: Text(sheetContext.tr('skip')),
            ),
          ],
        ),
      ),
    );

    if (watch != true || !context.mounted) return false;
    final earned = await _economyV3.earnHintWithRewardedInterstitial();
    if (!context.mounted) return earned;

    if (earned) {
      await store.addHints(1);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('+1 ${context.tr('hints')}')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('rewarded_ad_unavailable'))),
      );
    }
    return earned;
  }

  Future<void> _offerCareerDouble(
    BuildContext context,
    CareerRewardGrant grant,
  ) async {
    final watch = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => Padding(
        key: const ValueKey<String>('career-x2-rewarded-offer'),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.workspace_premium_rounded, size: 46),
            const SizedBox(height: 10),
            Text(
              'x2 ${sheetContext.tr('coin')}',
              textAlign: TextAlign.center,
              style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '+${grant.amount} ${sheetContext.tr('coin')}',
              textAlign: TextAlign.center,
              style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              icon: const Icon(Icons.ondemand_video_rounded),
              label: Text('x2 · ${sheetContext.tr('watch_rewarded_ad')}'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: Text(sheetContext.tr('skip')),
            ),
          ],
        ),
      ),
    );

    if (watch != true || !context.mounted) return;
    final result = await _economyV3.doubleCareerReward(
      level: grant.level,
      variant: grant.variant,
    );
    if (!context.mounted) return;

    if (result != null && result.granted && result.amount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('+${result.amount} ${context.tr('coin')} · x2'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('rewarded_ad_unavailable'))),
      );
    }
  }

  /// Kept for compatibility with older lifecycle callers. Loaded rewarded ads
  /// are owned and disposed by [AdsService].
  Future<void> disposeLoadedAd() async {}
}
