import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../widgets/adaptive_app_shell.dart';
import '../../widgets/player_avatar.dart';
import '../career/career_screen.dart';
import '../daily/daily_screen.dart';
import '../duel/matchmaking_screen.dart';
import '../economy/coin_store_screen.dart';
import '../tutorial/tutorial_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final EconomyService _economy = EconomyService.instance;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_onEconomyChanged);
    _economy.initialize();
  }

  @override
  void dispose() {
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app_name')),
        actions: [
          AnimatedBuilder(
            animation: widget.store,
            builder: (context, _) => Chip(
              avatar: const Icon(Icons.lightbulb_outline, size: 18),
              label: Text('${widget.store.hints}'),
            ),
          ),
          const SizedBox(width: 4),
          CoinPill(
            balance: _economy.balance,
            loading: _economy.loading && _economy.wallet == null,
            onPressed: () => _open(context, const CoinStoreScreen()),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _economy.refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: AnimatedBuilder(
                    animation: widget.store,
                    builder: (context, _) => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _PlayerSummary(store: widget.store, economy: _economy),
                        const SizedBox(height: 16),
                        _PrimaryHomeAction(
                          economy: _economy,
                          onQuickDuel: () =>
                              _open(context, const MatchmakingScreen()),
                        ),
                        const SizedBox(height: 24),
                        SectionHeader(title: context.tr('quick_modes')),
                        const SizedBox(height: 10),
                        ModeTile(
                          icon: Icons.casino_outlined,
                          title: context.tr('career'),
                          subtitle: context.tr('career_random_subtitle'),
                          onTap: () =>
                              _open(context, CareerScreen(store: widget.store)),
                        ),
                        const SizedBox(height: 10),
                        ModeTile(
                          icon: Icons.today_outlined,
                          title: context.tr('daily_sudoku'),
                          subtitle: context.tr('daily_subtitle'),
                          onTap: () =>
                              _open(context, DailyScreen(store: widget.store)),
                        ),
                        const SizedBox(height: 10),
                        ModeTile(
                          icon: Icons.emoji_events_outlined,
                          title: context.tr('ranked'),
                          subtitle: context.tr('online_duel_subtitle'),
                          onTap: () =>
                              _open(context, const MatchmakingScreen()),
                        ),
                        const SizedBox(height: 10),
                        ModeTile(
                          icon: Icons.school_outlined,
                          title: context.tr('practice'),
                          subtitle: widget.store.tutorialCompleted
                              ? context.tr('tutorial_repeat')
                              : context.tr('tutorial_new'),
                          onTap: () => _open(
                            context,
                            TutorialScreen(store: widget.store),
                          ),
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

  Future<void> _open(BuildContext context, Widget screen) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));
  }
}

class _PlayerSummary extends StatelessWidget {
  const _PlayerSummary({required this.store, required this.economy});

  final LocalProgressStore store;
  final EconomyService economy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        PlayerAvatar(
          displayName: context.tr('you'),
          avatarKey: 'home-${store.completedLevelCount}',
          radius: 24,
          semanticLabel: context.tr('player_avatar_semantics', <Object>[
            context.tr('you'),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('you'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                context.tr('completed_levels', <Object>[
                  store.completedLevelCount,
                ]),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        CoinPill(
          balance: economy.balance,
          loading: economy.loading && economy.wallet == null,
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CoinStoreScreen())),
        ),
      ],
    );
  }
}

class _PrimaryHomeAction extends StatelessWidget {
  const _PrimaryHomeAction({required this.economy, required this.onQuickDuel});

  final EconomyService economy;
  final VoidCallback onQuickDuel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('quick_duel'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('quick_duel_body'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onQuickDuel,
              icon: Icon(
                economy.canEnterOnline ? Icons.public : Icons.lock_outline,
              ),
              label: Text(
                economy.canEnterOnline
                    ? context.tr('find_opponent')
                    : context.tr('open_coin_store'),
              ),
            ),
            if (economy.error != null) ...[
              const SizedBox(height: 10),
              Text(economy.error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
