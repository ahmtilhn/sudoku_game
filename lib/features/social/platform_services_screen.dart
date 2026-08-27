import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';

class PlatformServicesScreen extends StatefulWidget {
  const PlatformServicesScreen({super.key});

  @override
  State<PlatformServicesScreen> createState() => _PlatformServicesScreenState();
}

class _PlatformServicesScreenState extends State<PlatformServicesScreen> {
  static const String _iconRoot =
      'assets/googleplayGameCenterleaderboardicon';

  final PlatformGameServices _games = PlatformGameServices.instance;
  bool _busy = false;
  String? _error;

  String get _platformTitle =>
      Platform.isIOS ? 'Game Center' : 'Google Play Games';

  String get _platformLogo => Platform.isIOS
      ? 'assets/logo/game_center_logo.png'
      : 'assets/logo/google_play_logo.png';

  @override
  void initState() {
    super.initState();
    unawaited(_refreshPlatformState());
  }

  Future<void> _refreshPlatformState() async {
    try {
      if (!await _games.isConfigured()) return;
      await _games.refreshAuthentication();
    } catch (_) {
      // Platform connection is informational here. Each feature still runs the
      // normal interactive authentication flow when the user opens it.
    }
  }

  Future<bool> _authenticate() async {
    if (!await _games.isConfigured()) return false;
    var authenticated = await _games.refreshAuthentication();
    if (!authenticated) authenticated = await _games.authenticate();
    return authenticated;
  }

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _authenticate()) {
        throw const PlatformGameServicesException(
          'authentication_failed',
          'Platform authentication could not be completed.',
        );
      }
      final opened = await action();
      if (!opened) {
        throw const PlatformGameServicesException(
          'unavailable',
          'The requested platform screen is not available.',
        );
      }
    } on PlatformGameServicesException catch (error) {
      if (mounted) {
        setState(
          () => _error = UserSafeError.message(
            context,
            error,
            fallback: error.message,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final difficultyItems = <_DifficultyLeaderboardData>[
      _DifficultyLeaderboardData(
        title: context.tr('difficulty_beginner'),
        asset: '$_iconRoot/beginner.png',
        accent: const Color(0xFF61D987),
        scope: PlatformLeaderboardScope.beginner,
      ),
      _DifficultyLeaderboardData(
        title: context.tr('difficulty_easy'),
        asset: '$_iconRoot/easy.png',
        accent: const Color(0xFF66C7FF),
        scope: PlatformLeaderboardScope.easy,
      ),
      _DifficultyLeaderboardData(
        title: context.tr('difficulty_medium'),
        asset: '$_iconRoot/medium.png',
        accent: const Color(0xFFFFC94D),
        scope: PlatformLeaderboardScope.medium,
      ),
      _DifficultyLeaderboardData(
        title: context.tr('difficulty_hard'),
        asset: '$_iconRoot/hard.png',
        accent: const Color(0xFFFF8A4C),
        scope: PlatformLeaderboardScope.hard,
      ),
      _DifficultyLeaderboardData(
        title: context.tr('difficulty_expert'),
        asset: '$_iconRoot/expert.png',
        accent: const Color(0xFFB7A9FF),
        scope: PlatformLeaderboardScope.expert,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  InPageHeader(title: _platformTitle),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: _games.authenticated,
                    builder: (context, connected, _) => _PlatformStatusCard(
                      platformTitle: _platformTitle,
                      logoAsset: _platformLogo,
                      connected: connected,
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(minHeight: 2),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _PlatformErrorCard(
                      title: context.tr('online_account_unavailable'),
                      message: _error!,
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    context.tr('leaderboards').toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .58),
                      fontSize: 12,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _FeaturedLeaderboardCard(
                    title: context.tr('global_elo'),
                    subtitle: 'Compete with the best players worldwide',
                    icon: const DuelAssetIcon(
                      DuelAsset.leaderboardCrownPro,
                      size: 70,
                    ),
                    accent: const Color(0xFF35D2FF),
                    onTap: _busy
                        ? null
                        : () => _run(
                            () => PlatformLeaderboardService.instance.show(
                              PlatformLeaderboardScope.global,
                            ),
                          ),
                  ),
                  const SizedBox(height: 9),
                  for (var index = 0; index < difficultyItems.length; index++) ...[
                    _DifficultyLeaderboardCard(
                      data: difficultyItems[index],
                      onTap: _busy
                          ? null
                          : () => _run(
                              () => PlatformLeaderboardService.instance.show(
                                difficultyItems[index].scope,
                              ),
                            ),
                    ),
                    if (index != difficultyItems.length - 1)
                      const SizedBox(height: 7),
                  ],
                  const SizedBox(height: 14),
                  _FeaturedLeaderboardCard(
                    title: context.tr('achievement_showcase'),
                    subtitle: 'View your highlights and milestones',
                    icon: const _PlatformLeaderboardAsset(
                      asset: '$_iconRoot/achievement.png',
                      size: 60,
                    ),
                    accent: const Color(0xFFB78BFF),
                    compact: true,
                    onTap: _busy ? null : () => _run(_games.showAchievements),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DifficultyLeaderboardData {
  const _DifficultyLeaderboardData({
    required this.title,
    required this.asset,
    required this.accent,
    required this.scope,
  });

  final String title;
  final String asset;
  final Color accent;
  final PlatformLeaderboardScope scope;
}

class _PlatformStatusCard extends StatelessWidget {
  const _PlatformStatusCard({
    required this.platformTitle,
    required this.logoAsset,
    required this.connected,
  });

  final String platformTitle;
  final String logoAsset;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final accent = connected
        ? const Color(0xFF61E28D)
        : const Color(0xFF7F8F9A);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B26).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF66C7FF).withValues(alpha: .24),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF07111A).withValues(alpha: .24),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 38,
            child: Image.asset(
              logoAsset,
              fit: BoxFit.contain,
              cacheWidth: 112,
              cacheHeight: 112,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => Icon(
                Icons.sports_esports_rounded,
                color: accent,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platformTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  connected ? 'Connected' : 'Connects when a feature is opened',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .10),
              border: Border.all(color: accent.withValues(alpha: .78)),
            ),
            child: Icon(
              connected ? Icons.check_rounded : Icons.more_horiz_rounded,
              size: 18,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedLeaderboardCard extends StatelessWidget {
  const _FeaturedLeaderboardCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final Widget icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(17);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          padding: EdgeInsets.fromLTRB(
            12,
            compact ? 10 : 12,
            11,
            compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: accent.withValues(alpha: .56)),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                accent.withValues(alpha: .14),
                const Color(0xFF0B1721).withValues(alpha: .93),
                const Color(0xFF09141D).withValues(alpha: .96),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .08),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: compact ? 66 : 78,
                height: compact ? 66 : 78,
                child: Center(child: icon),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .96),
                        fontSize: compact ? 16 : 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              _ChevronBubble(accent: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _DifficultyLeaderboardCard extends StatelessWidget {
  const _DifficultyLeaderboardCard({required this.data, required this.onTap});

  final _DifficultyLeaderboardData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(15);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          height: 60,
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1820).withValues(alpha: .88),
            borderRadius: radius,
            border: Border.all(
              color: data.accent.withValues(alpha: .22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: data.accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: data.accent.withValues(alpha: .14),
                  ),
                ),
                child: _PlatformLeaderboardAsset(
                  asset: data.asset,
                  size: 43,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w850,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ChevronBubble(accent: data.accent, small: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformLeaderboardAsset extends StatelessWidget {
  const _PlatformLeaderboardAsset({required this.asset, required this.size});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: 160,
      cacheHeight: 160,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
    );
  }
}

class _ChevronBubble extends StatelessWidget {
  const _ChevronBubble({required this.accent, this.small = false});

  final Color accent;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 28.0 : 32.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: .09),
        border: Border.all(color: accent.withValues(alpha: .14)),
      ),
      child: Icon(
        Icons.chevron_right_rounded,
        color: Colors.white.withValues(alpha: .78),
        size: small ? 20 : 22,
      ),
    );
  }
}

class _PlatformErrorCard extends StatelessWidget {
  const _PlatformErrorCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF785A).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF785A).withValues(alpha: .24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF9A82),
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .62),
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w650,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
