import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';

class HintEconomy {
  const HintEconomy._();

  static const int coinCost = 15;

  static Future<bool> consumeOrAcquire(
    BuildContext context,
    LocalProgressStore store,
  ) async {
    if (await store.consumeHint()) return true;
    if (!context.mounted) return false;

    final action = await showDialog<_HintAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('hints')),
        content: Text(context.tr('hints_count', const <Object>[0])),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(_HintAction.coin),
            icon: const Icon(Icons.monetization_on_outlined),
            label: Text(
              context.tr('continue_with_coins', const <Object>[coinCost]),
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_HintAction.rewardedAd),
            icon: const Icon(Icons.ondemand_video_outlined),
            label: Text(context.tr('watch_rewarded_ad')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('cancel')),
          ),
        ],
      ),
    );

    if (!context.mounted || action == null) return false;

    if (action == _HintAction.coin) {
      final purchased = await store.purchaseHint(coinCost: coinCost);
      if (!context.mounted) return false;
      if (!purchased) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('not_enough_coins'))),
        );
        return false;
      }
      return store.consumeHint();
    }

    final watched = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('watch_rewarded_ad')),
        content: Text(context.tr('rewarded_ad_prototype_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('continue_action')),
          ),
        ],
      ),
    );
    if (watched != true) return false;

    await store.addHints(1);
    return store.consumeHint();
  }
}

enum _HintAction { coin, rewardedAd }
