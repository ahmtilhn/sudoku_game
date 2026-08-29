#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'lib/features/economy/coin_store_screen.dart'
text = path.read_text(encoding='utf-8')

field = 'final EconomyV3Service _economyV3 = EconomyV3Service.instance;'
if text.count(field) != 1:
    raise SystemExit('coin_store: state field marker mismatch')
text = text.replace(field, field + '\n  int _productPage = 0;', 1)

start = text.index('  @override\n  Widget build(BuildContext context) {')
end_marker = '\n}\n\nclass _StorePanel extends StatelessWidget {'
end = text.index(end_marker, start)

build = r'''  @override
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
                                ? () => setState(
                                    () => _productPage = page - 1,
                                  )
                                : null,
                            onNext: page < pageCount - 1
                                ? () => setState(
                                    () => _productPage = page + 1,
                                  )
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
'''

text = text[:start] + build + text[end:]

pager = r'''
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

'''
marker = 'class _StorePanel extends StatelessWidget {'
if marker not in text:
    raise SystemExit('coin_store: store panel marker missing')
text = text.replace(marker, pager + marker, 1)
path.write_text(text, encoding='utf-8')
