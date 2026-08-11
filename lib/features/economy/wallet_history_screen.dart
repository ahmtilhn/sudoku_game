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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
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
                final maxWidth = constraints.maxWidth >= 840 ? 720.0 : 640.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        InPageHeader(
                          title: context.tr('coin_history'),
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
                        for (final entry in entries) ...[
                          _LedgerTile(entry: entry),
                          const SizedBox(height: 8),
                        ],
                      ],
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

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});

  final CoinLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final positive = entry.amount >= 0;
    final scheme = Theme.of(context).colorScheme;
    final amount = NumberFormat.decimalPattern().format(entry.amount.abs());
    final balance = NumberFormat.decimalPattern().format(entry.balanceAfter);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: positive
              ? scheme.primaryContainer.withValues(alpha: .72)
              : scheme.surfaceContainerHighest.withValues(alpha: .72),
          child: DuelAssetIcon(
            DuelAsset.coin,
            size: 22,
            color: positive
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          _reasonLabel(context, entry),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          context.tr('coin_history_balance_after', <Object>[
            DateFormat.yMMMd().add_Hm().format(entry.createdAt.toLocal()),
            balance,
          ]),
        ),
        trailing: Text(
          '${positive ? '+' : '-'}$amount',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: positive ? scheme.primary : scheme.onSurface,
          ),
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
