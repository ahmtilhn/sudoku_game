import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';

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
    await economy.refresh(showLoading: false);
    if (!context.mounted) return false;

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
              style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('hints_count', const <Object>[0]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: economy.balance >= coinCost
                  ? () => Navigator.of(sheetContext).pop(_HintAction.coin)
                  : null,
              icon: const Icon(Icons.monetization_on_outlined),
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

    if (action == _HintAction.coin) {
      try {
        await FirebaseSessionService.ensureAnonymousSession();
        final snapshot = await EconomyApiClient.instance.spendCareerContinue(
          'hint:${DateTime.now().microsecondsSinceEpoch}',
        );
        await economy.applyPurchaseWallet(snapshot);
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
      } on EconomyApiException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
        return false;
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('try_again_when_connected'))),
          );
        }
        return false;
      }
    }

    final watched = await AdsService.instance.showRewarded();
    if (!context.mounted) return false;
    if (!watched) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('rewarded_ad_unavailable'))),
      );
      return false;
    }

    await store.addHints(1);
    return store.consumeHint();
  }
}

enum _HintAction { coin, rewardedAd }
