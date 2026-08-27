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
  static const _iconRoot = 'assets/googleplayGameCenterleaderboardicon';
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
      if (await _games.isConfigured()) {
        await _games.refreshAuthentication();
      }
    } catch (_) {
      // Native platform state is informative only on this page.
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
      if (!await action()) {
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
    final difficulties = <_LeaderboardItem>[
      _LeaderboardItem(
        title: context.tr('difficulty_beginner'),
        asset: '$_iconRoot/beginner.png',
        accent: const Color(0xFF61D987),
        scope: PlatformLeaderboardScope.beginner,
      ),
      _LeaderboardItem(
        title: context.tr('difficulty_easy'),
        asset: '$_iconRoot/easy.png',
        accent: const Color(0xFF66C7FF),
        scope: PlatformLeaderboardScope.easy,
      ),
      _LeaderboardItem(
        title: context.tr('difficulty_medium'),
        asset: '$_iconRoot/medium.png',
        accent: const Color(0xFFFFC94D),
        scope: PlatformLeaderboardScope.medium,
      ),
      _LeaderboardItem(
        title: context.tr('difficulty_hard'),
        asset: '$_iconRoot/hard.png',
        accent: const Color(0xFFFF8A4C),
        scope: PlatformLeaderboardScope.hard,
      ),
      _LeaderboardItem(
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
                    builder: (_, connected, _) => _PlatformStatusCard(
                      title: _platformTitle,
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
                    _ErrorCard(
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
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LeaderboardCard(
                    title: context.tr('global_elo'),
                    subtitle: 'Compete with the best players worldwide',
                    accent: const Color(0xFF35D2FF),
                    featured: true,
                    icon: const DuelAssetIcon(
                      DuelAsset.leaderboardCrownPro,
                      size: 70,
                    ),
                    onTap: _busy
                        ? null
                        : () => _run(
                            () => PlatformLeaderboardService.instance.show(
                              PlatformLeaderboardScope.global,
                            ),
                          ),
                  ),
                  const SizedBox(height: 9),
                  for (var i = 0; i < difficulties.length; i++) ...[
                    _LeaderboardCard(
                      title: difficulties[i].title,
                      accent: difficulties[i].accent,
                      icon: _AssetIcon(
                        asset: difficulties[i].asset,
                        size: 43,
                      ),
                      onTap: _busy
                          ? null
                          : () => _run(
                              () => PlatformLeaderboardService.instance.show(
                                difficulties[i].scope,
                              ),
                            ),
                    ),
                    if (i != difficulties.length - 1)
                      const SizedBox(height: 7),
                  ],
                  const SizedBox(height: 14),
                  _LeaderboardCard(
                    title: context.tr('achievement_showcase'),
                    subtitle: 'View your highlights and milestones',
                    accent: const Color(0xFFB78BFF),
                    featured: true,
                    compactFeatured: true,
                    icon: const _AssetIcon(
                      asset:
                          'assets/googleplayGameCenterleaderboardicon/achievement.png',
                      size: 60,
                    ),
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

class _LeaderboardItem {
  const _LeaderboardItem({
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
    required this.title,
    required this.logoAsset,
    required this.connected,
  });

  final String title;
  final String logoAsset;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final accent = connected
        ? const Color(0xFF61E28D)
        : const Color(0xFF7F8F9A);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B26).withValues(alpha: .84),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF66C7FF).withValues(alpha: .24),
        ),
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
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .10),
              border: Border.all(color: accent.withValues(alpha: .70)),
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

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.title,
    required this.accent,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.featured = false,
    this.compactFeatured = false,
  });

  final String title;
  final String? subtitle;
  final Color accent;
  final Widget icon;
  final VoidCallback? onTap;
  final bool featured;
  final bool compactFeatured;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(featured ? 17 : 15);
    final height = featured ? (compactFeatured ? 86.0 : 102.0) : 60.0;
    final iconBox = featured ? (compactFeatured ? 66.0 : 78.0) : 46.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: featured
                ? null
                : const Color(0xFF0C1820).withValues(alpha: .88),
            gradient: featured
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      accent.withValues(alpha: .14),
                      const Color(0xFF0B1721).withValues(alpha: .93),
                      const Color(0xFF09141D).withValues(alpha: .96),
                    ],
                  )
                : null,
            borderRadius: radius,
            border: Border.all(
              color: accent.withValues(alpha: featured ? .52 : .22),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: iconBox,
                height: iconBox,
                child: Center(child: icon),
              ),
              SizedBox(width: featured ? 10 : 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: featured ? 18 : 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: featured ? 32 : 28,
                height: featured ? 32 : 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: .09),
                  border: Border.all(color: accent.withValues(alpha: .14)),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: .78),
                  size: featured ? 22 : 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetIcon extends StatelessWidget {
  const _AssetIcon({required this.asset, required this.size});

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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.title, required this.message});

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
                    fontWeight: FontWeight.w600,
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
