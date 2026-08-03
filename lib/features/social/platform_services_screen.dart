import 'dart:io';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/responsive_layout.dart';

class PlatformServicesScreen extends StatefulWidget {
  const PlatformServicesScreen({super.key});

  @override
  State<PlatformServicesScreen> createState() =>
      _PlatformServicesScreenState();
}

class _PlatformServicesScreenState extends State<PlatformServicesScreen> {
  final PlatformGameServices _games = PlatformGameServices.instance;

  bool _busy = true;
  bool _configured = false;
  bool _authenticated = false;
  PlatformPlayer? _player;
  String? _error;

  String get _platformTitle =>
      Platform.isIOS ? 'Game Center' : 'Google Play Games';

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final configured = await _games.isConfigured();
      var authenticated = false;
      PlatformPlayer? player;
      if (configured) {
        authenticated = await _games.refreshAuthentication();
        player = authenticated ? _games.localPlayer.value : null;
        if (authenticated) {
          await PlatformLeaderboardService.instance.syncAuthoritativeRatings();
        }
      }
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _authenticated = authenticated;
        _player = player;
      });
    } on PlatformGameServicesException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _authenticate() async {
    if (!await _games.isConfigured()) {
      if (mounted) setState(() => _configured = false);
      return false;
    }
    var authenticated = await _games.refreshAuthentication();
    if (!authenticated) authenticated = await _games.authenticate();
    if (mounted) {
      setState(() {
        _configured = true;
        _authenticated = authenticated;
        _player = authenticated ? _games.localPlayer.value : null;
      });
    }
    return authenticated;
  }

  Future<void> _connect() async {
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
      await PlatformLeaderboardService.instance.syncAuthoritativeRatings();
    } on PlatformGameServicesException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ResponsiveMetrics.of(context);
    final player = _player;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('leaderboards')),
        actions: [
          IconButton(
            tooltip: context.tr('refresh'),
            onPressed: _busy ? null : _refreshStatus,
            icon: const DuelAssetIcon(DuelAsset.refresh, size: 22),
          ),
        ],
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  metrics.pagePadding,
                  12,
                  metrics.pagePadding,
                  32,
                ),
                children: [
                  _PlatformHero(
                    platformTitle: _platformTitle,
                    configured: _configured,
                    authenticated: _authenticated,
                    player: player,
                    busy: _busy,
                    onConnect: _connect,
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 4),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const DuelAssetIcon(DuelAsset.cloud, size: 26),
                        title: Text(context.tr('online_account_unavailable')),
                        subtitle: Text(_error!),
                        trailing: IconButton(
                          tooltip: context.tr('retry'),
                          onPressed: _busy ? null : _refreshStatus,
                          icon: const DuelAssetIcon(
                            DuelAsset.refresh,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _SectionHeader(
                    asset: DuelAsset.trophy,
                    title: context.tr('leaderboards'),
                    subtitle: _platformTitle,
                  ),
                  const SizedBox(height: 10),
                  _FeaturedLeaderboardCard(
                    enabled: !_busy && _configured,
                    onTap: () => _run(
                      () => PlatformLeaderboardService.instance.show(
                        PlatformLeaderboardScope.global,
                      ),
                    ),
                    title: context.tr('global_elo'),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns =
                          constraints.maxWidth >= 560 && !metrics.hasVeryLargeText;
                      final width = twoColumns
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth;
                      final items = <_LeaderboardItem>[
                        _LeaderboardItem(
                          title: context.tr('difficulty_beginner'),
                          scope: PlatformLeaderboardScope.beginner,
                          accent: const Color(0xFF29D398),
                          asset: DuelAsset.grid,
                        ),
                        _LeaderboardItem(
                          title: context.tr('difficulty_easy'),
                          scope: PlatformLeaderboardScope.easy,
                          accent: const Color(0xFF3AA9FF),
                          asset: DuelAsset.target,
                        ),
                        _LeaderboardItem(
                          title: context.tr('difficulty_medium'),
                          scope: PlatformLeaderboardScope.medium,
                          accent: const Color(0xFFFFC94D),
                          asset: DuelAsset.shield,
                        ),
                        _LeaderboardItem(
                          title: context.tr('difficulty_hard'),
                          scope: PlatformLeaderboardScope.hard,
                          accent: const Color(0xFFFF8A3D),
                          asset: DuelAsset.swords,
                        ),
                        _LeaderboardItem(
                          title: context.tr('difficulty_expert'),
                          scope: PlatformLeaderboardScope.expert,
                          accent: const Color(0xFFFF5C7A),
                          asset: DuelAsset.diamond,
                        ),
                      ];
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final item in items)
                            SizedBox(
                              width: width,
                              child: _DifficultyLeaderboardCard(
                                item: item,
                                enabled: !_busy && _configured,
                                onTap: () => _run(
                                  () => PlatformLeaderboardService.instance.show(
                                    item.scope,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    asset: DuelAsset.diamond,
                    title: context.tr('achievement_showcase'),
                    subtitle: _platformTitle,
                  ),
                  const SizedBox(height: 10),
                  _AchievementCard(
                    enabled: !_busy && _configured,
                    onTap: () => _run(_games.showAchievements),
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

class _PlatformHero extends StatelessWidget {
  const _PlatformHero({
    required this.platformTitle,
    required this.configured,
    required this.authenticated,
    required this.player,
    required this.busy,
    required this.onConnect,
  });

  final String platformTitle;
  final bool configured;
  final bool authenticated;
  final PlatformPlayer? player;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final connected = configured && authenticated;
    final displayName = player?.displayName ?? platformTitle;
    final accent = connected
        ? const Color(0xFF29D398)
        : const Color(0xFF3AA9FF);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101B20).withValues(alpha: .96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .1), blurRadius: 28),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 460 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final identity = Row(
            children: [
              PlayerAvatar(
                displayName: displayName,
                avatarKey: 'platform-$displayName',
                remoteApprovedImageUrl: player?.avatarUrl,
                radius: 31,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          connected
                              ? Icons.check_circle_rounded
                              : Icons.link_off_rounded,
                          color: accent,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            connected
                                ? '$platformTitle · Connected'
                                : '$platformTitle · Not connected',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .64),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
          final connectButton = FilledButton.icon(
            onPressed: busy || connected || !configured ? null : onConnect,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const DuelAssetIcon(DuelAsset.people, size: 20),
            label: Text(connected ? 'Connected' : 'Connect'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                if (!connected) ...[
                  const SizedBox(height: 14),
                  connectButton,
                ],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              if (!connected) ...[
                const SizedBox(width: 12),
                connectButton,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.asset,
    required this.title,
    required this.subtitle,
  });

  final String asset;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DuelAssetIcon(asset, size: 28),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: .5)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeaturedLeaderboardCard extends StatelessWidget {
  const _FeaturedLeaderboardCard({
    required this.enabled,
    required this.onTap,
    required this.title,
  });

  final bool enabled;
  final VoidCallback onTap;
  final String title;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFC94D);
    return Card(
      color: const Color(0xFF17231C).withValues(alpha: .98),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: accent.withValues(alpha: .48)),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: const DuelAssetIcon(
                  DuelAsset.trophy,
                  size: 47,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr('current_elo'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardItem {
  const _LeaderboardItem({
    required this.title,
    required this.scope,
    required this.accent,
    required this.asset,
  });

  final String title;
  final PlatformLeaderboardScope scope;
  final Color accent;
  final String asset;
}

class _DifficultyLeaderboardCard extends StatelessWidget {
  const _DifficultyLeaderboardCard({
    required this.item,
    required this.enabled,
    required this.onTap,
  });

  final _LeaderboardItem item;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF101B20).withValues(alpha: .96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(19),
        side: BorderSide(color: item.accent.withValues(alpha: .3)),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: DuelAssetIcon(
                  item.asset,
                  size: 31,
                  color: item.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: item.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7A5CFF);
    return Card(
      color: const Color(0xFF171426).withValues(alpha: .97),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: accent.withValues(alpha: .42)),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              const DuelAssetIcon(
                DuelAsset.diamond,
                size: 48,
                color: Color(0xFFB9A8FF),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('achievement_showcase'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr('achievement_showcase_empty'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
