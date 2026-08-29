import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/ux_feedback.dart';

class WalletHistoryScreen extends StatefulWidget {
  const WalletHistoryScreen({super.key});

  @override
  State<WalletHistoryScreen> createState() => _WalletHistoryScreenState();
}

class _WalletHistoryScreenState extends State<WalletHistoryScreen> {
  Future<List<CoinLedgerEntry>>? _entries;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _page = 0;
      _entries = EconomyApiClient.instance.loadLedger(limit: 100);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<CoinLedgerEntry>>(
          future: _entries,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: UxStatePanel.error(
                    context,
                    message: UserSafeError.message(context, snapshot.error),
                    onRetry: _reload,
                  ),
                ),
              );
            }
            final entries = snapshot.data ?? const <CoinLedgerEntry>[];
            if (entries.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: UxStatePanel.empty(
                    context,
                    title: context.tr('coin_history_empty'),
                    message: context.tr('coin_history_empty'),
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 680;
                final maxWidth = constraints.maxWidth >= 840 ? 720.0 : 640.0;
                final availableForRows =
                    (constraints.maxHeight - (compact ? 114 : 132)).clamp(
                      190.0,
                      double.infinity,
                    );
                final targetRowHeight = compact ? 76.0 : 90.0;
                final itemsPerPage = (availableForRows / targetRowHeight)
                    .floor()
                    .clamp(2, 7);
                final pageCount = (entries.length / itemsPerPage).ceil();
                final safePage = _page.clamp(0, pageCount - 1);
                if (safePage != _page) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _page != safePage) {
                      setState(() => _page = safePage);
                    }
                  });
                }
                final start = safePage * itemsPerPage;
                final end = (start + itemsPerPage).clamp(0, entries.length);
                final visibleEntries = entries.sublist(start, end);

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        constraints.maxWidth < 360 ? 12 : 16,
                        compact ? 4 : 8,
                        constraints.maxWidth < 360 ? 12 : 16,
                        compact ? 8 : 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InPageHeader(
                            title: context.tr('coin_history'),
                            padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                            actions: [
                              IconButton(
                                tooltip: context.tr('refresh'),
                                onPressed: _reload,
                                icon: const DuelAssetIcon(
                                  DuelAsset.refresh,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < visibleEntries.length;
                                  index++
                                )
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        bottom:
                                            index == visibleEntries.length - 1
                                            ? 0
                                            : compact
                                            ? 5
                                            : 8,
                                      ),
                                      child: _LedgerTile(
                                        entry: visibleEntries[index],
                                        compact: compact,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (pageCount > 1) ...[
                            SizedBox(height: compact ? 6 : 10),
                            _HistoryPager(
                              page: safePage,
                              pageCount: pageCount,
                              onPrevious: safePage > 0
                                  ? () => setState(() => _page = safePage - 1)
                                  : null,
                              onNext: safePage < pageCount - 1
                                  ? () => setState(() => _page = safePage + 1)
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HistoryPager extends StatelessWidget {
  const _HistoryPager({
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
      height: 44,
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '${page + 1} / $pageCount',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton.filledTonal(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry, required this.compact});

  final CoinLedgerEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final positive = entry.amount >= 0;
    final scheme = Theme.of(context).colorScheme;
    final amount = NumberFormat.decimalPattern().format(entry.amount.abs());
    final balance = NumberFormat.decimalPattern().format(entry.balanceAfter);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 12,
          vertical: compact ? 6 : 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: compact ? 17 : 20,
              backgroundColor: positive
                  ? scheme.primaryContainer.withValues(alpha: .72)
                  : scheme.surfaceContainerHighest.withValues(alpha: .72),
              child: DuelAssetIcon(
                DuelAsset.coin,
                size: compact ? 18 : 22,
                color: positive
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: compact ? 8 : 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _reasonLabel(context, entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 12 : 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('coin_history_balance_after', <Object>[
                      DateFormat.yMMMd().add_Hm().format(
                        entry.createdAt.toLocal(),
                      ),
                      balance,
                    ]),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 6 : 10),
            Text(
              '${positive ? '+' : '-'}$amount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: compact ? 13 : null,
                fontWeight: FontWeight.w900,
                color: positive ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _reasonLabel(BuildContext context, CoinLedgerEntry entry) {
    if (entry.reason == 'career_continue' &&
        entry.referenceId?.startsWith('hint:') == true) {
      return context.tr('ledger_hint_purchase');
    }
    return switch (entry.reason) {
      'starter_grant' => context.tr('ledger_starter_grant'),
      'match_entry' => context.tr('ledger_match_entry'),
      'match_payout' => context.tr('ledger_match_payout'),
      'match_refund' => context.tr('ledger_match_refund'),
      'daily_login' => context.tr('ledger_daily_login'),
      'daily_rewarded_ad' => context.tr('ledger_daily_rewarded_ad'),
      'career_rewarded_ad' => context.tr('ledger_career_rewarded_ad'),
      'achievement_reward' => context.tr('ledger_achievement_reward'),
      'career_continue' => context.tr('ledger_career_continue'),
      'hint_purchase' => context.tr('ledger_hint_purchase'),
      'store_purchase' => context.tr('ledger_store_purchase'),
      'purchase_refund' => context.tr('ledger_purchase_refund'),
      _ => entry.reason.replaceAll('_', ' '),
    };
  }
}
