import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';

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
      appBar: AppBar(
        title: Text(context.tr('coin_history')),
        actions: [
          IconButton(
            tooltip: context.tr('refresh'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
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
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 42),
                      const SizedBox(height: 12),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _reload,
                        child: Text(context.tr('try_again')),
                      ),
                    ],
                  ),
                ),
              );
            }
            final entries = snapshot.data ?? const <CoinLedgerEntry>[];
            if (entries.isEmpty) {
              return Center(child: Text(context.tr('coin_history_empty')));
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth >= 840 ? 720.0 : 640.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return _LedgerTile(entry: entries[index]);
                      },
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
    final amountLabel = '${positive ? '+' : '-'}$amount';
    final amountStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w900,
      color: positive ? scheme.primary : scheme.onSurface,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: positive
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            child: Icon(
              positive ? Icons.add_rounded : Icons.remove_rounded,
              color: positive
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          title: Text(
            _reasonLabel(context, entry),
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('coin_history_balance_after', <Object>[
                  DateFormat.yMMMd().add_Hm().format(entry.createdAt.toLocal()),
                  balance,
                ]),
              ),
              if (compact) ...[
                const SizedBox(height: 4),
                Text(amountLabel, style: amountStyle),
              ],
            ],
          ),
          trailing: compact ? null : Text(amountLabel, style: amountStyle),
        );
      },
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
