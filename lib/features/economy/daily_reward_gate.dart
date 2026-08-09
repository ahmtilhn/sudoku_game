import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ads_service.dart';
import '../../services/economy_v3_api_client.dart';
import '../../services/economy_v3_service.dart';
import '../../widgets/duel_asset_icon.dart';

class DailyRewardGate extends StatefulWidget {
  const DailyRewardGate({super.key, required this.child});

  final Widget child;

  @override
  State<DailyRewardGate> createState() => _DailyRewardGateState();
}

class _DailyRewardGateState extends State<DailyRewardGate> {
  final EconomyV3Service _economy = EconomyV3Service.instance;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkDailyReward());
    });
  }

  Future<void> _checkDailyReward() async {
    if (_checked || !mounted) return;
    _checked = true;
    await _economy.initialize();
    if (!mounted) return;
    final result = await _economy.claimDailyIfAvailable();
    if (!mounted || result == null || !result.granted || result.reward == null) {
      return;
    }
    await _showRewardDialog(result);
  }

  Future<void> _showRewardDialog(EconomyV3ClaimResult result) async {
    final reward = result.reward!;
    var doubling = false;
    var doubled = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canDouble =
                reward.isCoin &&
                !AdsService.instance.noAds &&
                (result.state.canDoubleLastCoinReward || doubled);
            return AlertDialog(
              backgroundColor: const Color(0xFF111A1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Colors.white.withValues(alpha: .12)),
              ),
              title: Text(
                'Day ${result.cycleDay ?? result.state.dailyCycleDay} reward',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (reward.isCoin)
                    const DuelAssetIcon(DuelAsset.coin, size: 54)
                  else
                    const Icon(
                      Icons.refresh_rounded,
                      size: 54,
                      color: Color(0xFFFFC94D),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    reward.isCoin
                        ? '+${reward.amount} Coins'
                        : '+1 Hint Refill',
                    style: const TextStyle(
                      color: Color(0xFFFFC94D),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reward.isCoin
                        ? (doubled
                              ? 'Daily reward doubled.'
                              : 'Come back tomorrow to continue your 30-day track.')
                        : 'A Hint Refill restores an empty hint meter to full.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                if (canDouble && !doubled)
                  FilledButton.icon(
                    onPressed: doubling
                        ? null
                        : () async {
                            setDialogState(() => doubling = true);
                            final doubledResult =
                                await _economy.doubleLastDailyReward();
                            if (!mounted) return;
                            setDialogState(() {
                              doubling = false;
                              doubled = doubledResult?.granted == true;
                            });
                          },
                    icon: const Icon(Icons.ondemand_video_rounded),
                    label: Text(
                      doubling ? 'Loading…' : 'Watch ad · +${reward.amount}',
                    ),
                  ),
                TextButton(
                  onPressed: doubling ? null : () => Navigator.of(context).pop(),
                  child: Text(doubled ? 'Continue' : 'Collect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
