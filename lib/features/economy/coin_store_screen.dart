import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

import '../../localization/app_strings.dart';
import '../../services/coin_store_service.dart';
import '../../services/economy_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import 'wallet_history_screen.dart';

class CoinStoreScreen extends StatefulWidget {
  const CoinStoreScreen({super.key});

  @override
  State<CoinStoreScreen> createState() => _CoinStoreScreenState();
}

class _CoinStoreScreenState extends State<CoinStoreScreen> {
  final CoinStoreService _store = CoinStoreService.instance;
  final EconomyService _economy = EconomyService.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_refresh);
    _economy.addListener(_refresh);
    unawaited(_store.initialize());
    unawaited(_economy.initialize());
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    _economy.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    await Future.wait<void>([
      _store.refreshProducts(),
      _economy.refresh(),
    ]);
  }

  Future<void> _claimDaily() async {
    final claimed = await _economy.claimDailyLogin();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          claimed
              ? context.tr('coin_added_wallet', <Object>[
                  _economy.wallet?.dailyLoginAmount ?? 50,
                ])
              : _economy.error ?? context.tr('try_again'),
        ),
      ),
    );
  }

  Future<void> _claimAd() async {
    final claimed = await _economy.claimDailyRewardedAd();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          claimed
              ? context.tr('coin_added_wallet', <Object>[
                  _economy.wallet?.dailyAdAmount ?? 50,
                ])
              : _economy.error ?? context.tr('rewarded_ad_unavailable'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('coin_store')),
        actions: [
          IconButton(
            tooltip: context.tr('coin_history'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const WalletHistoryScreen()),
            ),
            icon: const DuelAssetIcon(DuelAsset.notes, size: 22),
          ),
        ],
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
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
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final sidePadding =
                    (constraints.maxWidth - maxWidth).clamp(0, double.infinity) /
                            2 +
                        16;

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _CenteredStoreSection(
                        maxWidth: maxWidth,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: _BalanceCard(
                          balance: _economy.balance,
                          loading: _economy.loading,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _CenteredStoreSection(
                        maxWidth: maxWidth,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _DailyRewardsCard(
                          wallet: _economy.wallet,
                          noAds: _economy.noAds,
                          loginBusy: _economy.claimingDaily,
                          adBusy: _economy.showingDailyAd,
                          onClaimLogin: _claimDaily,
                          onClaimAd: _claimAd,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _CenteredStoreSection(
                        maxWidth: maxWidth,
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
                    if (_store.error != null || _economy.error != null)
                      SliverToBoxAdapter(
                        child: _CenteredStoreSection(
                          maxWidth: maxWidth,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: ListTile(
                              leading: const Icon(Icons.cloud_off_outlined),
                              title: Text(_store.error ?? _economy.error!),
                              trailing: IconButton(
                                tooltip: context.tr('retry'),
                                onPressed: _reload,
                                icon: const DuelAssetIcon(
                                  DuelAsset.refresh,
                                  size: 24,
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
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _store.error ?? context.tr('not_available_short'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          sidePadding,
                          0,
                          sidePadding,
                          32,
                        ),
                        sliver: SliverGrid.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            mainAxisExtent: columns == 1
                                ? (largeText ? 224 : 184)
                                : (largeText ? 260 : 220),
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

class _CenteredStoreSection extends StatelessWidget {
  const _CenteredStoreSection({
    required this.maxWidth,
    required this.padding,
    required this.child,
  });

  final double maxWidth;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _StoreArtwork extends StatelessWidget {
  const _StoreArtwork({
    required this.asset,
    this.size = 54,
    this.background,
  });

  final String asset;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .24),
        child: DecoratedBox(
          decoration: BoxDecoration(color: background ?? Colors.transparent),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: DuelAssetIcon(
              asset,
              size: size - 4,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.loading});

  final int balance;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF101B20).withValues(alpha: .96),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const _StoreArtwork(
              asset: DuelAsset.coinStoreBalancePro,
              size: 52,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('your_balance'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .68),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      loading
                          ? '…'
                          : context.tr('coin_amount', <Object>[
                              NumberFormat.decimalPattern().format(balance),
                            ]),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyRewardsCard extends StatelessWidget {
  const _DailyRewardsCard({
    required this.wallet,
    required this.noAds,
    required this.loginBusy,
    required this.adBusy,
    required this.onClaimLogin,
    required this.onClaimAd,
  });

  final dynamic wallet;
  final bool noAds;
  final bool loginBusy;
  final bool adBusy;
  final VoidCallback onClaimLogin;
  final VoidCallback onClaimAd;

  @override
  Widget build(BuildContext context) {
    final loginAvailable = wallet?.dailyLoginAvailable == true;
    final adAvailable = wallet?.dailyAdAvailable == true && !noAds;
    final reset = wallet?.nextDailyResetAt as DateTime?;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF14231D).withValues(alpha: .96),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _StoreArtwork(asset: DuelAsset.gift, size: 54),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('home_daily_reward_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (reset != null)
                        Text(
                          '${context.tr('time')}: ${DateFormat.Hm().format(reset.toLocal())}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .62),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: loginAvailable && !loginBusy ? onClaimLogin : null,
                  icon: loginBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const DuelAssetIcon(DuelAsset.gift, size: 22),
                  label: Text(
                    context.tr('claim_daily_coin', <Object>[
                      wallet?.dailyLoginAmount ?? 50,
                    ]),
                  ),
                ),
                if (!noAds)
                  OutlinedButton.icon(
                    onPressed: adAvailable && !adBusy ? onClaimAd : null,
                    icon: adBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ondemand_video_outlined),
                    label: Text(
                      context.tr('watch_ad_for_coin', <Object>[
                        wallet?.dailyAdAmount ?? 50,
                      ]),
                    ),
                  ),
              ],
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
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF111D27).withValues(alpha: .96),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;
            final info = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _StoreArtwork(asset: DuelAsset.removeAdsPro, size: 54),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('no_ads_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        owned
                            ? context.tr('no_ads_owned')
                            : context.tr('no_ads_body'),
                        maxLines: narrow ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .68),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            final actions = owned
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF29D398),
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      FilledButton.tonal(
                        onPressed: enabled && !pending ? onBuy : null,
                        child: pending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                product?.price ??
                                    context.tr('not_available_short'),
                              ),
                      ),
                      TextButton(
                        onPressed: enabled ? onRestore : null,
                        child: Text(context.tr('restore_purchases')),
                      ),
                    ],
                  );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: 8),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                Flexible(child: actions),
              ],
            );
          },
        ),
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

    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF101B20).withValues(alpha: .96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: (popular
                  ? const Color(0xFFFFC94D)
                  : const Color(0xFF29D398))
              .withValues(alpha: .32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (popular)
                  Chip(
                    label: Text(context.tr('popular')),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            Row(
              children: [
                _StoreArtwork(
                  asset: popular ? DuelAsset.diamond : DuelAsset.coin,
                  size: 38,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      NumberFormat.decimalPattern().format(coins),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
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
                    : Text(product.price),
              ),
            ),
          ],
        ),
      ),
    );
  }
}