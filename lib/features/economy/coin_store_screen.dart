import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

import '../../localization/app_strings.dart';
import '../../services/coin_store_service.dart';
import '../../services/economy_service.dart';
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
    _store.addListener(_onChanged);
    _economy.addListener(_onChanged);
    _store.initialize();
    _economy.initialize();
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _economy.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('coin_store')),
        actions: [
          IconButton(
            tooltip: context.tr('coin_history'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletHistoryScreen()),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width < 360
                ? 1
                : width < 600
                ? (width >= 430 ? 2 : 1)
                : width < 840
                ? 2
                : 3;
            final maxWidth = width >= 840 ? 960.0 : 720.0;
            return RefreshIndicator(
              onRefresh: () async {
                await Future.wait<void>(<Future<void>>[
                  _store.refreshProducts(),
                  _economy.refresh(),
                ]);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: _BalanceHeader(
                            balance: _economy.balance,
                            loading: _economy.loading,
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Material(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: scheme.onErrorContainer,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _store.error ?? _economy.error!,
                                        style: TextStyle(
                                          color: scheme.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverLayoutBuilder(
                      builder: (context, sliverConstraints) {
                        final available = sliverConstraints.crossAxisExtent;
                        final contentWidth = available > maxWidth
                            ? maxWidth
                            : available;
                        final side = (available - contentWidth) / 2;
                        return SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: side),
                          sliver: _store.loading && _store.products.isEmpty
                              ? const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 12,
                                        childAspectRatio: columns == 1
                                            ? 2.35
                                            : 1.15,
                                      ),
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final product = _store.coinProducts[index];
                                    final pending =
                                        _store.pendingProductId == product.id;
                                    return _CoinPackageCard(
                                      productId: product.id,
                                      coins: _store.coinAmount(product.id),
                                      title: product.title,
                                      description: product.description,
                                      price: product.price,
                                      pending: pending,
                                      enabled:
                                          _store.pendingProductId == null &&
                                          !_economy.processingPurchase,
                                      onBuy: () => _store.buy(product.id),
                                    );
                                  }, childCount: _store.coinProducts.length),
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.balance, required this.loading});

  final int balance;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final formatted = NumberFormat.decimalPattern().format(balance);
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Icon(
              Icons.monetization_on_rounded,
              color: scheme.onPrimaryContainer,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('your_balance'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    loading ? '…' : '$formatted Coin',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
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

class _CoinPackageCard extends StatelessWidget {
  const _CoinPackageCard({
    required this.productId,
    required this.coins,
    required this.title,
    required this.description,
    required this.price,
    required this.pending,
    required this.enabled,
    required this.onBuy,
  });

  final String productId;
  final int coins;
  final String title;
  final String description;
  final String price;
  final bool pending;
  final bool enabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final number = NumberFormat.decimalPattern().format(coins);
    final popular = productId == 'coins_5000';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (popular)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      context.tr('popular'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.monetization_on_rounded, color: scheme.tertiary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: enabled && !pending ? onBuy : null,
                child: pending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(price),
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
    final scheme = Theme.of(context).colorScheme;
    final price = product?.price ?? context.tr('not_available_short');
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.block, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('no_ads_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    owned
                        ? context.tr('no_ads_owned')
                        : context.tr('no_ads_body'),
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (owned)
              Icon(Icons.check_circle, color: scheme.onSecondaryContainer)
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonal(
                    onPressed: enabled && !pending ? onBuy : null,
                    child: pending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(price),
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
    );
  }
}
