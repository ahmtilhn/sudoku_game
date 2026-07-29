import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../widgets/adaptive_app_shell.dart';
import '../../widgets/player_avatar.dart';
import '../career/career_screen.dart';
import '../duel/matchmaking_screen.dart';
import '../economy/coin_store_screen.dart';
import '../settings/settings_screen.dart';
import '../social/player_profile_screen.dart';

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
          IconButton(
            tooltip: context.tr('profile'),
            onPressed: () => _open(context, const PlayerProfileScreen()),
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: context.tr('settings'),
            onPressed: () =>
                _open(context, SettingsScreen(store: widget.store)),
            icon: const Icon(Icons.settings_outlined),
          ),
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
                        const SizedBox(height: 18),
                        _ModeCard(
                          icon: Icons.casino_outlined,
                          title: context.tr('career'),
                          subtitle: context.tr('career_random_subtitle'),
                          supportingText: context.tr('career_intro'),
                          onTap: () =>
                              _open(context, CareerScreen(store: widget.store)),
                        ),
                        const SizedBox(height: 12),
                        _ModeCard(
                          icon: _economy.canEnterOnline
                              ? Icons.public
                              : Icons.lock_outline,
                          title: context.tr('online_duel'),
                          subtitle: context.tr('online_duel_subtitle'),
                          supportingText: context.tr(
                            'online_duel_fee_summary',
                            <Object>[_economy.minimumOnlineBalance],
                          ),
                          onTap: () =>
                              _open(context, const MatchmakingScreen()),
                        ),
                        if (_economy.error != null) ...[
                          const SizedBox(height: 12),
                          _InlineError(message: _economy.error!),
                        ],
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
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
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
                    context.tr('home_progress_summary', <Object>[
                      store.completedLevelCount,
                      economy.balance,
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.supportingText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String supportingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: Icon(icon, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      supportingText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
