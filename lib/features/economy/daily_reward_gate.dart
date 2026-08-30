import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
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
    if (!mounted ||
        result == null ||
        !result.granted ||
        result.reward == null) {
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
            final size = MediaQuery.sizeOf(context);
            final compact = size.width < 360 || size.height < 620;
            final veryCompact = size.height < 560;
            final canDouble =
                reward.isCoin &&
                !AdsService.instance.noAds &&
                (result.state.canDoubleLastCoinReward || doubled);
            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 24,
                vertical: compact ? 10 : 24,
              ),
              backgroundColor: const Color(0xFF111A1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 18 : 24),
                side: BorderSide(color: Colors.white.withValues(alpha: .12)),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: size.height - (compact ? 20 : 48),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    veryCompact
                        ? 12
                        : compact
                        ? 16
                        : 24,
                    compact ? 16 : 24,
                    veryCompact
                        ? 8
                        : compact
                        ? 10
                        : 14,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.tr('daily_reward_day_title', <Object>[
                          result.cycleDay ?? result.state.dailyCycleDay,
                        ]),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: veryCompact
                              ? 17
                              : compact
                              ? 18
                              : 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(
                        height: veryCompact
                            ? 9
                            : compact
                            ? 14
                            : 18,
                      ),
                      if (reward.isCoin)
                        DuelAssetIcon(
                          DuelAsset.coin,
                          size: veryCompact
                              ? 40
                              : compact
                              ? 46
                              : 54,
                        )
                      else
                        Icon(
                          Icons.refresh_rounded,
                          size: veryCompact
                              ? 40
                              : compact
                              ? 46
                              : 54,
                          color: const Color(0xFFFFC94D),
                        ),
                      SizedBox(
                        height: veryCompact
                            ? 8
                            : compact
                            ? 12
                            : 14,
                      ),
                      Text(
                        reward.isCoin
                            ? context.tr('coin_reward_value', <Object>[
                                reward.amount,
                              ])
                            : context.tr('hint_refill_reward_value'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFFFC94D),
                          fontSize: veryCompact
                              ? 19
                              : compact
                              ? 21
                              : 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: veryCompact ? 5 : 8),
                      Text(
                        reward.isCoin
                            ? (doubled
                                  ? context.tr('daily_reward_doubled')
                                  : context.tr('daily_reward_track_body'))
                            : context.tr('hint_refill_reward_body'),
                        textAlign: TextAlign.center,
                        maxLines: veryCompact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                          fontSize: veryCompact
                              ? 11
                              : compact
                              ? 12
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(
                        height: veryCompact
                            ? 10
                            : compact
                            ? 16
                            : 20,
                      ),
                      if (canDouble && !doubled) ...[
                        FilledButton.icon(
                          onPressed: doubling
                              ? null
                              : () async {
                                  setDialogState(() => doubling = true);
                                  final doubledResult = await _economy
                                      .doubleLastDailyReward();
                                  if (!mounted) return;
                                  setDialogState(() {
                                    doubling = false;
                                    doubled = doubledResult?.granted == true;
                                  });
                                },
                          icon: const Icon(Icons.ondemand_video_rounded),
                          label: Text(
                            doubling
                                ? context.tr('loading')
                                : context.tr('watch_ad_reward_value', <Object>[
                                    reward.amount,
                                  ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(height: veryCompact ? 4 : 8),
                      ],
                      TextButton(
                        onPressed: doubling
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(
                          doubled
                              ? context.tr('continue_action')
                              : context.tr('collect'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
