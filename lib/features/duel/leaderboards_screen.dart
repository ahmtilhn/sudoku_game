import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/social_api_client.dart';

class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<String> _scopes = <String>[
    'global',
    for (final difficulty in SudokuDifficulty.values) difficulty.name,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _scopes.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('leaderboards')),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: context.tr('global')),
            for (final difficulty in SudokuDifficulty.values)
              Tab(text: context.strings.difficultyLabel(difficulty)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [for (final scope in _scopes) _LeaderboardTab(scope: scope)],
      ),
    );
  }
}

class _LeaderboardTab extends StatefulWidget {
  const _LeaderboardTab({required this.scope});

  final String scope;

  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab> {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _future = SocialApiClient.instance.loadLeaderboard(widget.scope);
  }

  Future<void> _refresh() async {
    final future = SocialApiClient.instance.loadLeaderboard(widget.scope);
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final entries = (data['entries'] as List?) ?? const <Object?>[];
        if (entries.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(child: Text(context.tr('leaderboard_empty'))),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry =
                  (entries[index] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{};
              final games = (entry['gamesPlayed'] as num?)?.toInt() ?? 0;
              final winRate =
                  ((entry['winRate'] as num?)?.toDouble() ?? 0) * 100;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text('${entry['rank'] ?? index + 1}'),
                  ),
                  title: Text(entry['displayName']?.toString() ?? 'Player'),
                  subtitle: Text(
                    context.tr('leaderboard_row', <Object>[
                      games,
                      winRate.round(),
                    ]),
                  ),
                  trailing: Text(
                    '${entry['rating'] ?? 1000}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
