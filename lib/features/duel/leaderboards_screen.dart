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
    'friends',
    'country',
    'current_season',
    'daily_tournament',
    'weekend_tournament',
    'countries',
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
            for (final scope in _scopes) Tab(text: _scopeLabel(context, scope)),
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

String _scopeLabel(BuildContext context, String scope) {
  return switch (scope) {
    'global' => context.tr('global_elo'),
    'friends' => context.tr('friends'),
    'country' => context.tr('country'),
    'current_season' => context.tr('current_season'),
    'daily_tournament' => context.tr('daily_tournament'),
    'weekend_tournament' => context.tr('weekend_tournament'),
    'countries' => context.tr('countries'),
    _ =>
      SudokuDifficulty.values.any((difficulty) => difficulty.name == scope)
          ? context.strings.difficultyLabel(
              SudokuDifficulty.values.firstWhere(
                (difficulty) => difficulty.name == scope,
              ),
            )
          : scope,
  };
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
    _future = SocialApiClient.instance.loadCompetitiveLeaderboard(
      widget.scope,
      mode: widget.scope == 'friends' ? 'friends' : 'top',
    );
  }

  Future<void> _refresh() async {
    final future = SocialApiClient.instance.loadCompetitiveLeaderboard(
      widget.scope,
      mode: widget.scope == 'friends' ? 'friends' : 'top',
    );
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
              final country = entry['country']?.toString();
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text('${entry['rank'] ?? index + 1}'),
                  ),
                  title: Text(entry['displayName']?.toString() ?? 'Player'),
                  subtitle: Text(
                    [
                      context.tr('leaderboard_row', <Object>[
                        games,
                        winRate.round(),
                      ]),
                      if (country != null && country.isNotEmpty) country,
                    ].join(' · '),
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

  @override
  void didUpdateWidget(covariant _LeaderboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _future = SocialApiClient.instance.loadCompetitiveLeaderboard(
        widget.scope,
        mode: widget.scope == 'friends' ? 'friends' : 'top',
      );
    }
  }
}
