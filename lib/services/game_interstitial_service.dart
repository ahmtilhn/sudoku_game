import 'package:flutter/material.dart';

import '../data/local_progress_store.dart';
import '../localization/app_strings.dart';
import 'ads_service.dart';
import 'career_reward_sync_service.dart';
import 'economy_service.dart';
import 'economy_v3_service.dart';

enum GameInterstitialContext { careerWin, careerLoss, practice, normalPlay }

/// Central gate for post-game rewarded interstitials in offline play.
///
/// The ad is offered after every eligible completed offline game. There is no
/// frequency counter or cooldown. Rewarded interstitial policy requires a
/// disclosure and a way to skip before the ad starts, so this service owns that
/// small transition surface as well as the +1 Hint reward.
class GameInterstitialService {
  GameInterstitialService._();

  static final GameInterstitialService instance = GameInterstitialService._();

  final AdsService _ads = AdsService.instance;
  final EconomyV3Service _economyV3 = EconomyV3Service.instance;
  bool _showing = false;

  Future<bool> recordAndMaybeShow({
    required BuildContext context,
    required LocalProgressStore store,
    required GameInterstitialContext adContext,
  }) async {
    // Career progress is written locally first. Drain the V3 reward sync and
    // refresh the wallet before opening the post-game surface so the result
    // sheet can observe the authoritative Career Coin grant.
    if (adContext == GameInterstitialContext.careerWin) {
      await CareerRewardSyncService.instance.waitForIdle();
      await EconomyService.instance.refresh(showLoading: false);
    }

    if (_ads.noAds || _showing || !context.mounted) return false;
    if (!_ads.adsAvailable.value) await _ads.initialize();
    if (_ads.noAds || !_ads.adsAvailable.value || !context.mounted) return false;

    _showing = true;
    try {
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
    } finally {
      _showing = false;
    }
  }

  /// Kept for compatibility with older lifecycle callers. Loaded rewarded ads
  /// are owned and disposed by [AdsService].
  Future<void> disposeLoadedAd() async {}
}
