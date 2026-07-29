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
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B2638), Color(0xFF263247), Color(0xFF151D2C)],
          ),
        ),
        child: SafeArea(
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
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                        children: [
                          _HomeTopBar(
                            onProfile: () =>
                                _open(context, const PlayerProfileScreen()),
                            onSettings: () => _open(
                              context,
                              SettingsScreen(store: widget.store),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _PlayerSummary(
                            store: widget.store,
                            economy: _economy,
                          ),
                          const SizedBox(height: 12),
                          _DailyRewardPanel(
                            economy: _economy,
                            onTap: () =>
                                _open(context, const CoinStoreScreen()),
                          ),
                          const SizedBox(height: 12),
                          _OnlineHeroCard(
                            economy: _economy,
                            onTap: () =>
                                _open(context, const MatchmakingScreen()),
                          ),
                          const SizedBox(height: 12),
                          _HomeActionGrid(
                            store: widget.store,
                            onCareer: () => _open(
                              context,
                              CareerScreen(store: widget.store),
                            ),
                            onProfile: () =>
                                _open(context, const PlayerProfileScreen()),
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
      ),
    );
  }

  Future<void> _open(BuildContext context, Widget screen) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({required this.onProfile, required this.onSettings});

  final VoidCallback onProfile;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _CircleIconButton(
            tooltip: context.tr('profile'),
            icon: Icons.person_outline,
            onPressed: onProfile,
          ),
          Expanded(
            child: Text(
              context.tr('app_name').toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _CircleIconButton(
            tooltip: context.tr('settings'),
            icon: Icons.settings_outlined,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .08),
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: .14)),
      ),
      icon: Icon(icon),
    );
  }
}

class _PlayerSummary extends StatelessWidget {
  const _PlayerSummary({required this.store, required this.economy});

  final LocalProgressStore store;
  final EconomyService economy;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _CompactStat(
                      icon: Icons.emoji_events,
                      value: '${store.completedLevelCount}',
                      label: context.tr('home_progress_label'),
                      color: const Color(0xFFE8C15A),
                    ),
                    const SizedBox(width: 12),
                    _CompactStat(
                      icon: Icons.monetization_on_outlined,
                      value: '${economy.balance}',
                      label: context.tr('home_wallet_label'),
                      color: const Color(0xFF7BC6B2),
                    ),
                  ],
                ),
              ],
            ),
          ),
          CoinPill(
            balance: economy.balance,
            loading: economy.loading && economy.wallet == null,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const CoinStoreScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .70),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DailyRewardPanel extends StatelessWidget {
  const _DailyRewardPanel({required this.economy, required this.onTap});

  final EconomyService economy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFE8C15A).withValues(alpha: .16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFE8C15A).withValues(alpha: .38),
              ),
            ),
            child: const SizedBox(
              width: 58,
              height: 58,
              child: Icon(
                Icons.card_giftcard_rounded,
                color: Color(0xFFE8C15A),
                size: 34,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('home_daily_reward_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr('home_daily_reward_body'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              minimumSize: const Size(72, 40),
              backgroundColor: const Color(0xFF7BC6B2),
              foregroundColor: const Color(0xFF08201D),
            ),
            child: Text(context.tr('claim_daily_coin', const <Object>[20])),
          ),
        ],
      ),
    );
  }
}

class _OnlineHeroCard extends StatelessWidget {
  const _OnlineHeroCard({required this.economy, required this.onTap});

  final EconomyService economy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF35445B), Color(0xFF243047)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _SudokuMistPainter()),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .09),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .16),
                        ),
                      ),
                      child: const SizedBox(
                        width: 58,
                        height: 58,
                        child: Icon(
                          Icons.sports_martial_arts_rounded,
                          color: Color(0xFFE8C15A),
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('online_duel'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr('online_duel_subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .75),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(116, 38),
                        backgroundColor: const Color(0xFFE8C15A),
                        foregroundColor: const Color(0xFF332400),
                      ),
                      child: Text(context.tr('home_play_online_cta')),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 14,
                top: 12,
                child: _SmallPill(
                  icon: Icons.monetization_on_outlined,
                  text: context.tr('online_duel_fee_summary', <Object>[
                    economy.minimumOnlineBalance,
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeActionGrid extends StatelessWidget {
  const _HomeActionGrid({
    required this.store,
    required this.onCareer,
    required this.onProfile,
  });

  final LocalProgressStore store;
  final VoidCallback onCareer;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SmallActionCard(
            icon: Icons.casino_outlined,
            title: context.tr('career'),
            subtitle: context.tr('home_career_card_body'),
            value: '${store.completedLevelCount}',
            onTap: onCareer,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SmallActionCard(
            icon: Icons.badge_outlined,
            title: context.tr('profile'),
            subtitle: context.tr('shown_to_other_players'),
            value: context.tr('home_rating_label'),
            onTap: onProfile,
          ),
        ),
      ],
    );
  }
}

class _SmallActionCard extends StatelessWidget {
  const _SmallActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xFFE8C15A), size: 20),
                  const Spacer(),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .68),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFE8C15A), size: 13),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SudokuMistPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .045)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final dx = size.width * i / 6;
      final dy = size.height * i / 6;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), grid);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), grid);
    }

    final warm = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFFE8C15A).withValues(alpha: .16),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .72, size.height * .30),
              radius: size.width * .42,
            ),
          );
    canvas.drawRect(Offset.zero & size, warm);
  }

  @override
  bool shouldRepaint(covariant _SudokuMistPainter oldDelegate) => false;
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
