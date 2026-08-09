import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
import '../../services/economy_v3_service.dart';
import '../../widgets/duel_asset_icon.dart';

class HintEconomy {
  const HintEconomy._();

  static const int fallbackCoinCost = 25;

  static Future<bool> consumeOrAcquire(
    BuildContext context,
    LocalProgressStore store,
  ) async {
    if (await store.consumeHint()) return true;
    if (!context.mounted) return false;

    final economy = EconomyService.instance;
    final v3 = EconomyV3Service.instance;
    await Future.wait<void>([
      economy.refresh(showLoading: false),
      v3.initialize(),
    ]);
    if (!context.mounted) return false;

    final v3State = v3.state;
    final coinCost = v3State?.hintCoinCost ?? fallbackCoinCost;
    final refillCount = v3State?.hintRefills ?? 0;

    final action = await showModalBottomSheet<_HintAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('hints'),
              textAlign: TextAlign.center,
              style: Theme.of(
                sheetContext,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('hints_count', const <Object>[0]),
              textAlign: TextAlign.center,
            ),
            if (refillCount > 0) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(_HintAction.refill),
                icon: const Icon(Icons.refresh_rounded),
                label: Text('Use Hint Refill · ×$refillCount'),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: economy.balance >= coinCost
                  ? () => Navigator.of(sheetContext).pop(_HintAction.coin)
                  : null,
              icon: const DuelAssetIcon(DuelAsset.coin, size: 24),
              label: Text(
                '${context.tr('continue_with_coins', <Object>[coinCost])} · ${context.tr('balance_coin', <Object>[economy.balance])}',
              ),
            ),
            if (!AdsService.instance.noAds) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(_HintAction.rewardedAd),
                icon: const Icon(Icons.ondemand_video_outlined),
                label: Text(context.tr('watch_rewarded_ad')),
              ),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(context.tr('cancel')),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return false;

    if (action == _HintAction.refill) {
      final restored = await v3.consumeHintRefill();
      if (restored <= 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('try_again_when_connected'))),
          );
        }
        return false;
      }
      await store.addHints(restored);
      return store.consumeHint();
    }

    if (action == _HintAction.coin) {
      final purchased = await v3.purchaseHint(
        requestId: 'hint:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!context.mounted) return false;
      if (!purchased) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('try_again_when_connected'))),
        );
        return false;
      }
      await store.addHints(1);
      final consumed = await store.consumeHint();
      if (context.mounted && consumed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('coin_amount', <Object>[-coinCost])),
          ),
        );
      }
      return consumed;
    }

    final granted = await v3.earnHintWithAd();
    if (!context.mounted) return false;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('rewarded_ad_unavailable'))),
      );
      return false;
    }

    await store.addHints(1);
    return store.consumeHint();
  }
}

enum _HintAction { coin, rewardedAd, refill }
