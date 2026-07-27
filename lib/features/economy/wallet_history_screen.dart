import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
        title: const Text('Coin history'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
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
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final entries = snapshot.data ?? const <CoinLedgerEntry>[];
            if (entries.isEmpty) {
              return const Center(child: Text('No Coin activity yet.'));
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: positive
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        child: Icon(
          positive ? Icons.add_rounded : Icons.remove_rounded,
          color: positive ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        _reasonLabel(entry.reason),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${DateFormat.yMMMd().add_Hm().format(entry.createdAt.toLocal())} · Balance $balance',
      ),
      trailing: Text(
        '${positive ? '+' : '-'}$amount',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: positive ? scheme.primary : scheme.onSurface,
        ),
      ),
    );
  }

  String _reasonLabel(String reason) => switch (reason) {
    'starter_grant' => 'Starter Coins',
    'match_entry' => 'Online match entry',
    'match_payout' => 'Match prize',
    'match_refund' => 'Match refund',
    'daily_login' => 'Daily login reward',
    'daily_rewarded_ad' => 'Daily ad reward',
    'career_rewarded_ad' => 'Career ad reward',
    'achievement_reward' => 'Achievement reward',
    'career_continue' => 'Career continue',
    'hint_purchase' => 'Hint purchase',
    'store_purchase' => 'Coin Store purchase',
    'purchase_refund' => 'Purchase refund',
    _ => reason.replaceAll('_', ' '),
  };
}
