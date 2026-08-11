import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

import '../../localization/app_strings.dart';
import '../../services/coin_store_service.dart';
import '../../services/economy_service.dart';
import '../../services/economy_v3_api_client.dart';
import '../../services/economy_v3_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
import 'wallet_history_screen.dart';

class CoinStoreScreen extends StatefulWidget {
  const CoinStoreScreen({super.key});

  @override
  State<CoinStoreScreen> createState() => _CoinStoreScreenState();
}

class _CoinStoreScreenState extends State<CoinStoreScreen> {
  final CoinStoreService _store = CoinStoreService.instance;
  final EconomyService _economy = EconomyService.instance;
  final EconomyV3Service _economyV3 = EconomyV3Service.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_refresh);
    _economy.addListener(_refresh);
    _economyV3.addListener(_refresh);
    unawaited(_store.initialize());
    unawaited(_economy.initialize());
    unawaited(_economyV3.initialize());
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    _economy.removeListener(_refresh);
    _economyV3.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    await Future.wait<void>([
      _store.refreshProducts(),
      _economy.refresh(),
      _economyV3.refresh(),
    ]);
  }

  Future<void> _claimDaily() async {
    final result = await _economyV3.claimDailyIfAvailable();
    final claimed = result?.granted == true;
    await _economy.refresh(showLoading: false);
    if (!mounted) return;
    final reward = result?.reward;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          claimed
              ? reward == null
                    ? context.tr('coin_added_wallet', const <Object>[0])
                    : reward.isCoin
                    ? context.tr('coin_added_wallet', <Object>[reward.amount])
                    : context.tr('daily_hint_refill_reward')
              : _economy.error ?? context.tr('try_again'),
        ),
      ),
    );
  }

  Future<void> _claimAd() async {
    final result = await _economyV3.doubleLastDailyReward();
    final claimed = result?.granted == true;
    await _economy.refresh(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          claimed
              ? context.tr('coin_added_wallet', <Object>[result?.amount ?? 0])
              : _economy.error ?? context.tr('rewarded_ad_unavailable'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth >= 1000 ? 960.0 : 720.0;
                final columns = constraints.maxWidth >= 820
                    ? 3
                    : constraints.maxWidth >= 520
                    ? 2
                    : 1;
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                            child: Column(
                              children: [
                                InPageHeader(
                                  title: context.tr('coin_store'),
                                  actions: [
                                    IconButton(
                                      tooltip: context.tr('coin_history'),
                                      onPressed: () =>
                                          Navigator.of(context).push<void>(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const WalletHistoryScreen(),
                                            ),
                                          ),
                                      icon: const DuelAssetIcon(
                                        DuelAsset.notes,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                                _BalanceCard(
                                  balance: _economy.balance,
                                  loading: _economy.loading,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _DailyRewardsCard(
                              wallet: _economy.wallet,
                              state: _economyV3.state,
                              noAds: _economy.noAds,
                              loginBusy:
                                  _economy.claimingDaily || _economyV3.loading,
                              adBusy:
                                  _economy.showingDailyAd || _economyV3.loading,
                              onClaimLogin: _claimDaily,
                              onClaimAd: _claimAd,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            child: _NoAdsCard(
                              product: _store.noAdsProduct,
                              owned: _economy.noAds,
                              pending:
                                  _store.pendingProductId ==
                                  CoinStoreService.noAdsProductId,
                              enabled:
                                  _store.pendingProductId == null &&
                                  !_economy.processingPurchase,
                              onBuy: () => _store.buyNonConsumable(
                                CoinStoreService.noAdsProductId,
                              ),
                              onRestore: _store.restorePurchases,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_store.error != null || _economy.error != null)
                      SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: _StorePanel(
                                accent: Theme.of(context).colorScheme.error,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.cloud_off_outlined,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  title: Text(_store.error ?? _economy.error!),
                                  trailing: IconButton(
                                    tooltip: context.tr('retry'),
                                    onPressed: _reload,
                                    icon: const Icon(Icons.refresh_rounded),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_store.loading && _store.coinProducts.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_store.coinProducts.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            _store.error ?? context.tr('not_available_short'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          (constraints.maxWidth - maxWidth).clamp(
                                    0,
                                    double.infinity,
                                  ) /
                                  2 +
                              16,
                          0,
                          (constraints.maxWidth - maxWidth).clamp(
                                    0,
                                    double.infinity,
                                  ) /
                                  2 +
                              16,
                          32,
                        ),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: columns == 1 ? 2.35 : 1.02,
                              ),
                          itemCount: _store.coinProducts.length,
                          itemBuilder: (context, index) {
                            final product = _store.coinProducts[index];
                            return _CoinPackageCard(
                              product: product,
                              coins: _store.coinAmount(product.id),
                              pending: _store.pendingProductId == product.id,
                              enabled:
                                  _store.pendingProductId == null &&
                                  !_economy.processingPurchase,
                              onBuy: () => _store.buy(product.id),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StorePanel extends StatelessWidget {
  const _StorePanel({
    required this.child,
    this.accent = const Color(0xFF3AA9FF),
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.loading});

  final int balance;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return _StorePanel(
      accent: const Color(0xFFFFC94D),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const DuelAssetIcon(DuelAsset.coinStoreBalancePro, size: 58),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('your_balance'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .68),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  loading
                      ? '...'
                      : context.tr('coin_amount', <Object>[
                          NumberFormat.decimalPattern().format(balance),
                        ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyRewardsCard extends StatelessWidget {
  const _DailyRewardsCard({
    required this.wallet,
    required this.state,
    required this.noAds,
    required this.loginBusy,
    required this.adBusy,
    required this.onClaimLogin,
    required this.onClaimAd,
  });

  final dynamic wallet;
  final EconomyV3State? state;
  final bool noAds;
  final bool loginBusy;
  final bool adBusy;
  final VoidCallback onClaimLogin;
  final VoidCallback onClaimAd;

  @override
  Widget build(BuildContext context) {
    final loginAvailable =
        state?.dailyAvailable ?? wallet?.dailyLoginAvailable == true;
    final adAvailable =
        (state?.canDoubleLastCoinReward ?? wallet?.dailyAdAvailable == true) &&
        !noAds;
    final reset =
        state?.nextDailyResetAt ?? wallet?.nextDailyResetAt as DateTime?;
    final nextReward = state?.nextReward;
    final calendar = state?.calendar ?? const <EconomyV3Reward>[];
    final cycleDay = state?.dailyCycleDay ?? 1;
    final completedInCycle = state == null
        ? 0
        : state!.dailyAvailable
        ? cycleDay - 1
        : cycleDay;
    return _StorePanel(
      accent: const Color(0xFF29D398),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const DuelAssetIcon(
                DuelAsset.dailyRewardPro,
                size: 34,
                color: Color(0xFF29D398),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('home_daily_reward_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (reset != null) ...[
            const SizedBox(height: 4),
            Text(
              '${context.tr('time')}: ${DateFormat.Hm().format(reset.toLocal())}',
              style: TextStyle(color: Colors.white.withValues(alpha: .62)),
            ),
          ],
          if (calendar.isNotEmpty) ...[
            const SizedBox(height: 14),
            _DailyCalendarGrid(
              calendar: calendar,
              cycleDay: cycleDay,
              completedInCycle: completedInCycle,
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 460;
              final buttonWidth = stacked
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 8) / (noAds ? 1 : 2);
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: buttonWidth,
                    child: FilledButton.icon(
                      onPressed: loginAvailable && !loginBusy
                          ? onClaimLogin
                          : null,
                      icon: loginBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.card_giftcard_rounded),
                      label: Text(
                        nextReward == null
                            ? context.tr('home_daily_reward_title')
                            : nextReward.isCoin
                            ? context.tr('claim_daily_coin', <Object>[
                                nextReward.amount,
                              ])
                            : context.tr('claim_hint_refill'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (!noAds)
                    SizedBox(
                      width: buttonWidth,
                      child: OutlinedButton.icon(
                        onPressed: adAvailable && !adBusy ? onClaimAd : null,
                        icon: adBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.ondemand_video_outlined),
                        label: Text(
                          context.tr('watch_ad_for_coin', <Object>[
                            state?.dailyLastClaimAmount ??
                                wallet?.dailyAdAmount ??
                                50,
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DailyCalendarGrid extends StatelessWidget {
  const _DailyCalendarGrid({
    required this.calendar,
    required this.cycleDay,
    required this.completedInCycle,
  });

  final List<EconomyV3Reward> calendar;
  final int cycleDay;
  final int completedInCycle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 6 : 5;
        final tileWidth =
            (constraints.maxWidth - ((columns - 1) * 6)) / columns;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var index = 0; index < calendar.length; index++)
              SizedBox(
                width: tileWidth,
                child: _DailyCalendarTile(
                  day: index + 1,
                  reward: calendar[index],
                  claimed: index + 1 <= completedInCycle,
                  current: index + 1 == cycleDay,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DailyCalendarTile extends StatelessWidget {
  const _DailyCalendarTile({
    required this.day,
    required this.reward,
    required this.claimed,
    required this.current,
  });

  final int day;
  final EconomyV3Reward reward;
  final bool claimed;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final accent = current
        ? const Color(0xFF3AA9FF)
        : claimed
        ? const Color(0xFF29D398)
        : Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: current ? .28 : .18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: current ? .55 : .22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('daily_day_short', <Object>[day]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent.withValues(alpha: .95),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Icon(
              claimed
                  ? Icons.check_circle_rounded
                  : reward.isHintRefill
                  ? Icons.refresh_rounded
                  : Icons.monetization_on_rounded,
              size: 16,
              color: accent.withValues(alpha: .9),
            ),
            const SizedBox(height: 2),
            Text(
              reward.isCoin
                  ? '${reward.amount}'
                  : context.tr('hint_refill_short'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .78),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoAdsCard extends StatelessWidget {
  const _NoAdsCard({
    required this.product,
    required this.owned,
    required this.pending,
    required this.enabled,
    required this.onBuy,
    required this.onRestore,
  });

  final ProductDetails? product;
  final bool owned;
  final bool pending;
  final bool enabled;
  final VoidCallback onBuy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return _StorePanel(
      accent: const Color(0xFF3AA9FF),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(
              children: [
                const DuelAssetIcon(
                  DuelAsset.shield,
                  size: 34,
                  color: Color(0xFF3AA9FF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('no_ads_title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        owned
                            ? context.tr('no_ads_owned')
                            : context.tr('no_ads_body'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .68),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (owned)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF29D398))
          else
            Wrap(
              spacing: 6,
              children: [
                FilledButton.tonal(
                  onPressed: enabled && !pending ? onBuy : null,
                  child: pending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          product?.price ?? context.tr('not_available_short'),
                        ),
                ),
                TextButton(
                  onPressed: enabled ? onRestore : null,
                  child: Text(context.tr('restore_purchases')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CoinPackageCard extends StatelessWidget {
  const _CoinPackageCard({
    required this.product,
    required this.coins,
    required this.pending,
    required this.enabled,
    required this.onBuy,
  });

  final ProductDetails product;
  final int coins;
  final bool pending;
  final bool enabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final popular = product.id == 'coins_5000';
    final accent = popular ? const Color(0xFFFFC94D) : const Color(0xFF29D398);
    return _StorePanel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (popular) ...[
                const SizedBox(width: 8),
                _StoreChip(
                  label: context.tr('popular'),
                  asset: DuelAsset.diamond,
                  color: accent,
                ),
              ],
            ],
          ),
          Row(
            children: [
              const DuelAssetIcon(
                DuelAsset.coin,
                size: 26,
                color: Color(0xFFFFC94D),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  NumberFormat.decimalPattern().format(coins),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: enabled && !pending ? onBuy : null,
              child: pending
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      product.price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreChip extends StatelessWidget {
  const _StoreChip({
    required this.label,
    required this.asset,
    required this.color,
  });

  final String label;
  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuelAssetIcon(asset, size: 16),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
