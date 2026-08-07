import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/player_avatar.dart';

class PlatformServicesScreen extends StatefulWidget {
  const PlatformServicesScreen({super.key});

  @override
  State<PlatformServicesScreen> createState() => _PlatformServicesScreenState();
}

class _PlatformServicesScreenState extends State<PlatformServicesScreen> {
  final PlatformGameServices _games = PlatformGameServices.instance;
  final PlatformLeaderboardService _leaderboards =
      PlatformLeaderboardService.instance;

  bool _busy = false;
  PlatformLeaderboardMirrorResult? _lastSync;

  @override
  Widget build(BuildContext context) {
    final player = _games.localPlayer.value;
    final connected = _games.authenticated.value && player != null;
    final platformName = Platform.isIOS ? 'Game Center' : 'Google Play Games';
    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            platformName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1728).withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF7A5CFF).withValues(alpha: .42),
                        ),
                      ),
                      child: Row(
                        children: [
                          PlayerAvatar(
                            displayName: player?.displayName ?? 'Sudoku Player',
                            avatarKey: 'platform-services',
                            localAvatarBytes: player?.avatarBytes,
                            remoteApprovedImageUrl: player?.avatarUrl,
                            radius: 34,
                            semanticLabel: context.tr(
                              'player_avatar_semantics',
                              <Object>[player?.displayName ?? 'Sudoku Player'],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  player?.displayName ?? platformName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  connected
                                      ? context.tr('connected')
                                      : context.tr('try_again_when_connected'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: connected
                                        ? const Color(0xFF29D398)
                                        : Colors.white54,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            connected
                                ? Icons.verified_rounded
                                : Icons.link_off_rounded,
                            color: connected
                                ? const Color(0xFF29D398)
                                : Colors.white38,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView(
                        children: [
                          _ActionTile(
                            asset: DuelAsset.leaderboardCrownPro,
                            title: context.tr('leaderboards'),
                            subtitle: context.tr('global_elo'),
                            onTap: _busy
                                ? null
                                : () => _openLeaderboard(
                                    PlatformLeaderboardScope.global,
                                  ),
                          ),
                          const SizedBox(height: 8),
                          _ActionTile(
                            asset: DuelAsset.resultVictoryTrophyPro,
                            title: context.tr('achievements'),
                            subtitle: platformName,
                            onTap: _busy ? null : _openAchievements,
                          ),
                          const SizedBox(height: 8),
                          _ActionTile(
                            asset: DuelAsset.refresh,
                            title: context.tr('refresh'),
                            subtitle: _lastSync == null
                                ? platformName
                                : _lastSync!.status.name,
                            onTap: _busy ? null : _sync,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLeaderboard(PlatformLeaderboardScope scope) async {
    await _run(() async {
      final opened = await _leaderboards.show(scope);
      if (!opened && Platform.isIOS) {
        await _games.showLeaderboard();
      }
    });
  }

  Future<void> _openAchievements() => _run(() async {
        await _games.showAchievements();
      });

  Future<void> _sync() async {
    await _run(() async {
      final result = await _leaderboards.syncAuthoritativeRatings();
      if (mounted) setState(() => _lastSync = result);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        await GameModal.error(
          context,
          title: context.tr('profile'),
          message: UserSafeError.message(context, error),
          retryLabel: context.tr('continue_action'),
          cancelLabel: context.tr('cancel'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String asset;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728).withValues(alpha: .94),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: Row(
              children: [
                DuelAssetIcon(asset, size: 50),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .54),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
