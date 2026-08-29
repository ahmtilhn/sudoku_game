import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

import '../../localization/app_strings.dart';
import '../../services/coin_store_service.dart';
import '../../services/economy_service.dart';
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
  int _productPage = 0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              final maxWidth = constraints.maxWidth >= 1000 ? 960.0 : 720.0;
              final columns = constraints.maxWidth >= 700
                  ? 3
                  : constraints.maxWidth >= 340
                  ? 2
                  : 1;
              final rows = compact ? 1 : 2;
              final products = _store.coinProducts;
              final pageSize = columns * rows;
              final pageCount = products.isEmpty
                  ? 1
                  : (products.length / pageSize).ceil();
              final page = _productPage.clamp(0, pageCount - 1);
              final startIndex = page * pageSize;
              final endIndex = (startIndex + pageSize).clamp(
                0,
                products.length,
              );
              final visibleProducts = products.sublist(startIndex, endIndex);

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      constraints.maxWidth < 360 ? 10 : 16,
                      compact ? 4 : 10,
                      constraints.maxWidth < 360 ? 10 : 16,
                      compact ? 6 : 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InPageHeader(
                          title: context.tr('coin_store'),
                          padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                          actions: [
                            IconButton(
                              tooltip: context.tr('coin_history'),
                              onPressed: () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => const WalletHistoryScreen(),
                                ),
                              ),
                              icon: const DuelAssetIcon(
                                DuelAsset.notes,
                                size: 22,
                              ),
                            ),
                            IconButton(
                              tooltip: context.tr('refresh'),
                              onPressed: _reload,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        _BalanceCard(
                          balance: _economy.balance,
                          loading: _economy.loading,
                        ),
                        SizedBox(height: compact ? 6 : 10),
                        _NoAdsCard(
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
                        if (_store.error != null || _economy.error != null) ...[
                          SizedBox(height: compact ? 5 : 8),
                          _StorePanel(
                            accent: Theme.of(context).colorScheme.error,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _store.error ?? _economy.error!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.tr('retry'),
                                  onPressed: _reload,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: compact ? 5 : 9),
                        Expanded(
                          child: _store.loading && products.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : products.isEmpty
                              ? Center(
                                  child: Text(
                                    _store.error ??
                                        context.tr('not_available_short'),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 8,
                                        childAspectRatio: columns == 1
                                            ? compact
                                                  ? 1.25
                                                  : 1.1
                                            : compact
                                            ? .78
                                            : .72,
                                      ),
                                  itemCount: visibleProducts.length,
                                  itemBuilder: (context, index) {
                                    final product = visibleProducts[index];
                                    return _CoinPackageCard(
                                      product: product,
                                      coins: _store.coinAmount(product.id),
                                      pending:
                                          _store.pendingProductId == product.id,
                                      enabled:
                                          _store.pendingProductId == null &&
                                          !_economy.processingPurchase,
                                      onBuy: () => _store.buy(product.id),
                                    );
                                  },
                                ),
                        ),
                        if (pageCount > 1)
                          _StorePager(
                            page: page,
                            pageCount: pageCount,
                            onPrevious: page > 0
                                ? () => setState(() => _productPage = page - 1)
                                : null,
                            onNext: page < pageCount - 1
                                ? () => setState(() => _productPage = page + 1)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StorePager extends StatelessWidget {
  const _StorePager({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '${page + 1} / $pageCount',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
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
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: const DuelAssetIcon(
              DuelAsset.storeNoAds,
              size: 86,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('no_ads_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (owned)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF29D398),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilledButton.tonal(
                        onPressed: enabled && !pending ? onBuy : null,
                        child: pending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _coinArtForAmount(int coins) {
  return switch (coins) {
    100 => DuelAsset.storeCoins100,
    500 => DuelAsset.storeCoins500,
    1000 => DuelAsset.storeCoins1000,
    5000 => DuelAsset.storeCoins5000,
    10000 => DuelAsset.storeCoins10000,
    50000 => DuelAsset.storeCoins50000,
    100000 => DuelAsset.storeCoins100000,
    _ => DuelAsset.coin,
  };
}

String _coinPackLabel(BuildContext context, int coins) {
  final formatted = NumberFormat.decimalPattern().format(coins);
  return context.tr('coin_pack_title', <Object>[formatted]);
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
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    _coinArtForAmount(coins),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: .42),
                        ],
                      ),
                    ),
                  ),
                  if (popular)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _StoreChip(
                        label: context.tr('popular'),
                        asset: DuelAsset.diamond,
                        color: accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _coinPackLabel(context, coins),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.tr('coin_pack_body'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .62),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
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
