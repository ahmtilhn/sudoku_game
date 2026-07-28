import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../widgets/menu_card.dart';
import '../career/career_screen.dart';
import '../daily/daily_screen.dart';
import '../duel/matchmaking_screen.dart';
import '../economy/coin_store_screen.dart';
import '../settings/account_protection_screen.dart';
import '../settings/settings_screen.dart';
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
    final protectedAccount = FirebaseSessionService.isProtected;
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
          ActionChip(
            avatar: const Icon(Icons.monetization_on_outlined, size: 18),
            label: Text(
              _economy.loading && _economy.wallet == null
                  ? '…'
                  : NumberFormat.compact().format(_economy.balance),
            ),
            onPressed: () => _open(context, const CoinStoreScreen()),
          ),
          IconButton(
            tooltip: protectedAccount
                ? 'Player account protected'
                : 'Protect player account',
            onPressed: () async {
              await _open(context, const AccountProtectionScreen());
              if (mounted) setState(() {});
            },
            icon: Icon(
              protectedAccount ? Icons.shield : Icons.shield_outlined,
            ),
          ),
          IconButton(
            tooltip: context.tr('settings'),
            onPressed: () => _open(
              context,
              SettingsScreen(store: widget.store),
            ),
            icon: const Icon(Icons.settings_outlined),
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
                        if (!FirebaseSessionService.isProtected) ...[
                          _AccountProtectionBanner(
                            onOpen: () async {
                              await _open(
                                context,
                                const AccountProtectionScreen(),
                              );
                              if (mounted) setState(() {});
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        _WelcomePanel(store: widget.store),
                        const SizedBox(height: 12),
                        _EconomyPanel(economy: _economy),
                        const SizedBox(height: 18),
                        MenuCard(
                          icon: Icons.casino_outlined,
                          title: context.tr('career'),
                          subtitle: context.tr('career_random_subtitle'),
                          trailing: Text(
                            context.tr('completed_levels', <Object>[
                              widget.store.completedLevelCount,
                            ]),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onTap: () => _open(
                            context,
                            CareerScreen(store: widget.store),
                          ),
                        ),
                        const SizedBox(height: 12),
                        MenuCard(
                          icon: Icons.public,
                          title: context.tr('online_duel'),
                          subtitle:
                              '${context.tr('online_duel_subtitle')} · ${_economy.entryFee} Coin',
                          trailing: _economy.canEnterOnline
                              ? const Icon(Icons.chevron_right_rounded)
                              : const Icon(Icons.lock_outline_rounded),
                          onTap: () => _open(
                            context,
                            const MatchmakingScreen(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        MenuCard(
                          icon: Icons.today_outlined,
                          title: context.tr('daily_sudoku'),
                          subtitle: context.tr('daily_subtitle'),
                          onTap: () => _open(
                            context,
                            DailyScreen(store: widget.store),
                          ),
                        ),
                        const SizedBox(height: 12),
                        MenuCard(
                          icon: Icons.school_outlined,
                          title: context.tr('how_to_play'),
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
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class _AccountProtectionBanner extends StatelessWidget {
  const _AccountProtectionBanner({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Protect your player account',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onSecondaryContainer,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Link an email before buying Coins so your wallet, Friend ID and rating can be recovered after reinstall or device change.',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            TextButton(onPressed: onOpen, child: const Text('Protect')),
          ],
        ),
      ),
    );
  }
}

class _EconomyPanel extends StatelessWidget {
  const _EconomyPanel({required this.economy});

  final EconomyService economy;

  @override
  Widget build(BuildContext context) {
    final wallet = economy.wallet;
    final scheme = Theme.of(context).colorScheme;
    if (wallet == null && economy.loading) {
      return const SizedBox(
        height: 76,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (wallet == null) {
      return Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, color: scheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  economy.error ?? 'Coin balance is temporarily unavailable.',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              IconButton(
                tooltip: 'Retry',
                onPressed: economy.refresh,
                icon: Icon(Icons.refresh, color: scheme.onErrorContainer),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.card_giftcard_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Daily rewards',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CoinStoreScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Store'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final stack = constraints.maxWidth < 470;
                final login = _RewardButton(
                  icon: Icons.calendar_today_outlined,
                  label: wallet.dailyLoginAvailable
                      ? 'Claim +${wallet.dailyLoginAmount}'
                      : 'Login reward claimed',
                  busy: economy.claimingDaily,
                  onPressed: wallet.dailyLoginAvailable
                      ? economy.claimDailyLogin
                      : null,
                );
                final ad = _RewardButton(
                  icon: Icons.ondemand_video_outlined,
                  label: wallet.dailyAdAvailable
                      ? 'Watch +${wallet.dailyAdAmount}'
                      : 'Ad reward claimed',
                  busy: economy.showingDailyAd,
                  onPressed: wallet.dailyAdAvailable
                      ? economy.claimDailyRewardedAd
                      : null,
                );
                if (stack) {
                  return Column(
                    children: [
                      SizedBox(width: double.infinity, child: login),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: ad),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: login),
                    const SizedBox(width: 10),
                    Expanded(child: ad),
                  ],
                );
              },
            ),
            if (economy.error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  economy.error!,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RewardButton extends StatelessWidget {
  const _RewardButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final Future<bool> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: busy || onPressed == null
          ? null
          : () async {
              final success = await onPressed!();
              if (!context.mounted || !success) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Coin reward added.')),
              );
            },
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.tutorialCompleted
                ? context.tr('welcome_returning_title')
                : context.tr('welcome_new_title'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            store.tutorialCompleted
                ? context.tr('welcome_returning_body')
                : context.tr('welcome_new_body'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
