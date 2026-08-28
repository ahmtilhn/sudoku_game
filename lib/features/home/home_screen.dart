import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local_progress_store.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/player_profile_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
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
  PlayerProfilePreferences? _profile;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_onEconomyChanged);
    _economy.initialize();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await PlayerProfileService.instance.load();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // Home keeps a local fallback when the social backend is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _economy.refresh,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
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
                              displayName:
                                  _profile?.displayName ?? 'Sudoku Player',
                              completedLevels: widget.store.completedLevelCount,
                              balance: _economy.balance,
                              onProfile: () =>
                                  _open(context, const PlayerProfileScreen()),
                              onSettings: () => _open(
                                context,
                                SettingsScreen(store: widget.store),
                              ),
                            ),
                            const SizedBox(height: 42),
                            const _HomeBrandTitle(),
                            const SizedBox(height: 46),
                            _OnlineHeroCard(
                              economy: _economy,
                              onTap: () =>
                                  _open(context, const MatchmakingScreen()),
                            ),
                            const SizedBox(height: 16),
                            _HomeActionGrid(
                              store: widget.store,
                              onCareer: () => _open(
                                context,
                                CareerScreen(store: widget.store),
                              ),
                              onStore: () =>
                                  _open(context, const CoinStoreScreen()),
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
  const _HomeTopBar({
    required this.displayName,
    required this.completedLevels,
    required this.balance,
    required this.onProfile,
    required this.onSettings,
  });

  final String displayName;
  final int completedLevels;
  final int balance;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final profileWidth = (constraints.maxWidth - 176).clamp(96.0, 190.0);
        return SizedBox(
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: profileWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onProfile,
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(
                                0xFFFFC94D,
                              ).withValues(alpha: .46),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .28),
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: PlayerAvatar(
                            displayName: displayName,
                            avatarKey: 'home-profile-$displayName',
                            radius: 18,
                            semanticLabel: context.tr(
                              'player_avatar_semantics',
                              <Object>[displayName],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 170,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      children: [
                        _TopIconButton(
                          asset: DuelAsset.settings,
                          tooltip: context.tr('settings'),
                          onPressed: onSettings,
                        ),
                        const SizedBox(width: 6),
                        _TopStatPill(
                          asset: DuelAsset.trophy,
                          value: '$completedLevels',
                          color: const Color(0xFFFFC94D),
                        ),
                        const SizedBox(width: 6),
                        _TopStatPill(
                          asset: DuelAsset.coin,
                          value: NumberFormat.compact().format(balance),
                          color: const Color(0xFFFFC94D),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.asset,
    required this.tooltip,
    required this.onPressed,
  });

  final String asset;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        backgroundColor: const Color(0xFF0B1215).withValues(alpha: .72),
        side: BorderSide(color: Colors.white.withValues(alpha: .16)),
      ),
      icon: DuelAssetIcon(asset, size: 19),
    );
  }
}

class _TopStatPill extends StatelessWidget {
  const _TopStatPill({
    required this.asset,
    required this.value,
    required this.color,
  });

  final String asset;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1215).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuelAssetIcon(asset, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeMenuAsset {
  const _HomeMenuAsset._();

  static const online = DuelAsset.homeDuelEmblem;
  static const career = DuelAsset.homeCareerRelic;
  static const profile = DuelAsset.homeProfileCrest;
  static const store = DuelAsset.homeStoreChest;
}

class _HomeBrandTitle extends StatelessWidget {
  const _HomeBrandTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              context.tr('app_name').toUpperCase(),
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 46,
                height: .96,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
                shadows: [
                  Shadow(
                    color: Color(0xAA000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _HomeDivider(),
      ],
    );
  }
}

class _StoneMedallion extends StatelessWidget {
  const _StoneMedallion({
    required this.asset,
    required this.color,
    this.size = 46,
    this.iconSize = 26,
    this.tint = true,
  });

  final String asset;
  final Color color;
  final double size;
  final double iconSize;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0D171A).withValues(alpha: .78),
        border: Border.all(color: color.withValues(alpha: .34)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .13), blurRadius: 16),
        ],
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: DuelAssetIcon(asset, size: iconSize, color: tint ? color : null),
      ),
    );
  }
}

class _HomeDivider extends StatelessWidget {
  const _HomeDivider();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            const Color(0xFFFFC94D).withValues(alpha: .42),
            const Color(0xFF29D398).withValues(alpha: .28),
            Colors.transparent,
          ],
        ),
      ),
      child: const SizedBox(width: 128, height: 1),
    );
  }
}

class _HomePanelDecoration extends Decoration {
  const _HomePanelDecoration({required this.accent, this.prominent = false});

  final Color accent;
  final bool prominent;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _HomePanelPainter(accent: accent, prominent: prominent);
}

class _HomePanelPainter extends BoxPainter {
  const _HomePanelPainter({required this.accent, required this.prominent});

  final Color accent;
  final bool prominent;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size ?? Size.zero;
    final rect = offset & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(prominent ? 24 : 20),
    );

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF172226).withValues(alpha: prominent ? .88 : .70),
          const Color(0xFF071014).withValues(alpha: prominent ? .94 : .78),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, fill);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: prominent ? .52 : .28),
          Colors.white.withValues(alpha: .10),
          const Color(0xFFFFC94D).withValues(alpha: prominent ? .28 : .16),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(.5), stroke);

    final glint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: prominent ? .26 : .12);
    canvas.drawLine(
      rect.topLeft + const Offset(22, 1),
      rect.topRight + const Offset(-42, 1),
      glint,
    );
  }
}

class _HomeMetaPillData {
  const _HomeMetaPillData({
    required this.asset,
    required this.label,
    required this.color,
  });

  final String asset;
  final String label;
  final Color color;
}

class _HomeMetaPill extends StatelessWidget {
  const _HomeMetaPill({
    required this.asset,
    required this.label,
    required this.color,
  });

  final String asset;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuelAssetIcon(asset, size: 13, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .82),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
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
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Ink(
          height: 132,
          decoration: const _HomePanelDecoration(
            accent: Color(0xFF29D398),
            prominent: true,
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              const _StoneMedallion(
                asset: _HomeMenuAsset.online,
                color: Color(0xFF29D398),
                size: 72,
                iconSize: 58,
                tint: false,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.tr('online_duel'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('online_duel_subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _HomeMetaPill(
                          asset: DuelAsset.coin,
                          label: context.tr('online_duel_fee_summary', <Object>[
                            economy.minimumOnlineBalance,
                          ]),
                          color: const Color(0xFFFFC94D),
                        ),
                        _HomeMetaPill(
                          asset: DuelAsset.people,
                          label: context.tr('same_variant_match'),
                          color: const Color(0xFF29D398),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: DuelAssetIcon(
                  DuelAsset.arrowForward,
                  size: 22,
                  color: const Color(0xFF29D398).withValues(alpha: .88),
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
    required this.onStore,
    required this.onProfile,
  });

  final LocalProgressStore store;
  final VoidCallback onCareer;
  final VoidCallback onStore;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SmallActionCard(
          asset: _HomeMenuAsset.career,
          title: context.tr('career'),
          subtitle: context.tr('home_career_card_body'),
          value: '${store.completedLevelCount}',
          valueAsset: DuelAsset.trophy,
          accent: const Color(0xFFFFC94D),
          height: 116,
          chips: [
            _HomeMetaPillData(
              asset: DuelAsset.trophy,
              label: context.tr('completed_levels', <Object>[
                store.completedLevelCount,
              ]),
              color: const Color(0xFFFFC94D),
            ),
            _HomeMetaPillData(
              asset: DuelAsset.target,
              label: context.tr('mistakes_limit_count', <Object>[0, 3]),
              color: const Color(0xFFFFC94D),
            ),
          ],
          onTap: onCareer,
        ),
        const SizedBox(height: 10),
        _SmallActionCard(
          asset: _HomeMenuAsset.store,
          title: context.tr('coin_store'),
          subtitle: context.tr('home_daily_reward_body'),
          value: NumberFormat.compact().format(EconomyService.instance.balance),
          valueAsset: DuelAsset.coin,
          accent: const Color(0xFF29D398),
          onTap: onStore,
        ),
        const SizedBox(height: 10),
        _SmallActionCard(
          asset: _HomeMenuAsset.profile,
          title: context.tr('profile'),
          subtitle: context.tr('shown_to_other_players'),
          value: context.tr('home_rating_label'),
          valueAsset: DuelAsset.trophy,
          accent: const Color(0xFF3AA9FF),
          onTap: onProfile,
        ),
      ],
    );
  }
}

class _SmallActionCard extends StatelessWidget {
  const _SmallActionCard({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.valueAsset,
    required this.accent,
    required this.onTap,
    this.height = 92,
    this.chips = const [],
  });

  final String asset;
  final String title;
  final String subtitle;
  final String value;
  final String valueAsset;
  final Color accent;
  final VoidCallback onTap;
  final double height;
  final List<_HomeMetaPillData> chips;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: _HomePanelDecoration(accent: accent),
          child: Row(
            children: [
              _StoneMedallion(
                asset: asset,
                color: accent,
                size: 54,
                iconSize: 44,
                tint: false,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: chips.isEmpty ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final chip in chips)
                            _HomeMetaPill(
                              asset: chip.asset,
                              label: chip.label,
                              color: chip.color,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DuelAssetIcon(valueAsset, size: 16, color: accent),
                  const SizedBox(width: 5),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent.withValues(alpha: .92),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              DuelAssetIcon(
                DuelAsset.arrowForward,
                size: 18,
                color: accent.withValues(alpha: .80),
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
            DuelAssetIcon(
              DuelAsset.cloud,
              size: 22,
              color: scheme.onErrorContainer,
            ),
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
