import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
import '../../services/economy_v3_service.dart';
import '../../widgets/duel_asset_icon.dart';

class HintEconomy {
  const HintEconomy._();

  // The backend currently exposes one protected career-spend transaction.
  // Hints use that server-authoritative transaction so every Coin shown in the
  // UI comes from the same wallet and cannot drift from a local balance.
  static const int coinCost = 25;

  static Future<bool> consumeOrAcquire(
    BuildContext context,
    LocalProgressStore store,
  ) async {
    if (await store.consumeHint()) return true;
    if (!context.mounted) return false;

    final economy = EconomyService.instance;
    final economyV3 = EconomyV3Service.instance;
    await Future.wait<void>([
      economy.refresh(showLoading: false),
      economyV3.refresh(),
    ]);
    if (!context.mounted) return false;

    final state = economyV3.state;
    final refillCount = state?.hintRefills ?? 0;
    final refillSize = state?.hintRefillSize ?? 3;

    final action = await showModalBottomSheet<_HintAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF111A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
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
            const SizedBox(height: 16),
            if (refillCount > 0) ...[
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(_HintAction.refill),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  context.tr('use_hint_refill', <Object>[
                    refillCount,
                    refillSize,
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: economy.balance >= coinCost
                  ? () => Navigator.of(sheetContext).pop(_HintAction.coin)
                  : null,
              icon: const DuelAssetIcon(
                DuelAsset.coin,
                size: 18,
                color: Color(0xFFFFC94D),
              ),
              label: Text(
                '${context.tr('continue_with_coins', const <Object>[coinCost])} · ${context.tr('balance_coin', <Object>[economy.balance])}',
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
      final consumedRefillSize = await economyV3.consumeHintRefill();
      if (consumedRefillSize > 0) {
        await store.addHints(consumedRefillSize);
        return store.consumeHint();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('hint_refill_unavailable'))),
        );
      }
      return false;
    }

    if (action == _HintAction.coin) {
      final purchased = await economyV3.purchaseHint(
        requestId: 'hint:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (purchased) {
        await economy.refresh(showLoading: false);
        await store.addHints(1);
        final consumed = await store.consumeHint();
        if (context.mounted && consumed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr('coin_amount', const <Object>[-coinCost]),
              ),
            ),
          );
        }
        return consumed;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              economyV3.error ??
                  economy.error ??
                  context.tr('not_enough_coins'),
            ),
          ),
        );
      }
      return false;
    }

    final earned = await economyV3.earnHintWithAd();
    if (!context.mounted) return false;
    if (!earned) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('rewarded_ad_unavailable'))),
      );
      return false;
    }

    await store.addHints(1);
    return store.consumeHint();
  }
}

enum _HintAction { refill, coin, rewardedAd }
