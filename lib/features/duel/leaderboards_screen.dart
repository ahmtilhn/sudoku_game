import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
import '../../services/player_profile_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/player_avatar.dart';

class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen> {
  static const List<PlatformLeaderboardScope> _scopes =
      <PlatformLeaderboardScope>[
        PlatformLeaderboardScope.global,
        PlatformLeaderboardScope.beginner,
        PlatformLeaderboardScope.easy,
        PlatformLeaderboardScope.medium,
        PlatformLeaderboardScope.hard,
        PlatformLeaderboardScope.expert,
      ];

  final SocialApiClient _social = SocialApiClient.instance;
  final PlatformLeaderboardService _platform =
      PlatformLeaderboardService.instance;
  final PlatformGameServices _games = PlatformGameServices.instance;

  final Map<PlatformLeaderboardScope, _LeaderboardSnapshot> _snapshots =
      <PlatformLeaderboardScope, _LeaderboardSnapshot>{};

  PlayerProfilePreferences? _profile;
  bool _loading = true;
  bool _openingNative = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _games.localPlayer.addListener(_refreshPlatformIdentity);
    unawaited(_load());
  }

  @override
  void dispose() {
    _games.localPlayer.removeListener(_refreshPlatformIdentity);
    super.dispose();
  }

  void _refreshPlatformIdentity() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profileFuture = PlayerProfileService.instance.load();
      final results = await Future.wait(
        _scopes.map((scope) async {
          final response = await _social.loadCompetitiveLeaderboard(
            _scopeKey(scope),
            mode: 'around_me',
          );
          return MapEntry(scope, _LeaderboardSnapshot.fromJson(response));
        }),
      );
      final profile = await profileFuture;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _snapshots
          ..clear()
          ..addEntries(results);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNative(PlatformLeaderboardScope scope) async {
    if (_openingNative) return;
    setState(() => _openingNative = true);
    try {
      final opened = await _platform.show(scope);
      if (!opened && defaultTargetPlatform == TargetPlatform.iOS) {
        final fallback = await _games.showLeaderboard();
        if (fallback) return;
      }
      if (!opened && mounted) {
        await GameModal.warning(
          context,
          title: context.tr('leaderboards'),
          message: context.tr('try_again_when_connected'),
          confirmLabel: context.tr('continue_action'),
        );
      }
    } catch (error) {
      if (mounted) {
        await GameModal.error(
          context,
          title: context.tr('leaderboards'),
          message: UserSafeError.message(context, error),
          retryLabel: context.tr('try_again'),
          cancelLabel: context.tr('cancel'),
        );
      }
    } finally {
      if (mounted) setState(() => _openingNative = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platformPlayer = _games.localPlayer.value;
    final name = _profile?.displayName.trim().isNotEmpty == true
        ? _profile!.displayName
        : platformPlayer?.displayName ?? 'Sudoku Player';
    final platformName = defaultTargetPlatform == TargetPlatform.iOS
        ? 'Game Center'
        : 'Google Play Games';

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Column(
                  children: [
                    _Header(
                      busy: _loading,
                      onBack: () => Navigator.of(context).pop(),
                      onRefresh: _load,
                    ),
                    const SizedBox(height: 8),
                    _Hero(
                      name: name,
                      platformName: platformName,
                      player: platformPlayer,
                      global: _snapshots[PlatformLeaderboardScope.global],
                    ),
                    const SizedBox(height: 10),
                    Expanded(child: _body(platformName)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(String platformName) {
    if (_loading && _snapshots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DuelAssetIcon(DuelAsset.statusOfflinePro, size: 112),
              const SizedBox(height: 12),
              Text(
                UserSafeError.message(context, _error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.tr('retry')),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 460
            ? 2
            : 1;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: _scopes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            mainAxisExtent: 142,
          ),
          itemBuilder: (context, index) {
            final scope = _scopes[index];
            return _LeaderboardCard(
              label: _scopeLabel(context, scope),
              platformName: platformName,
              snapshot: _snapshots[scope],
              accent: _scopeColor(scope),
              busy: _openingNative,
              onTap: () => _openNative(scope),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.busy,
    required this.onBack,
    required this.onRefresh,
  });

  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: onBack,
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const SizedBox(width: 8),
          const DuelAssetIcon(DuelAsset.leaderboardCrownPro, size: 38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('leaderboards'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: context.tr('refresh'),
            onPressed: busy ? null : onRefresh,
            icon: busy
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.name,
    required this.platformName,
    required this.player,
    required this.global,
  });

  final String name;
  final String platformName;
  final PlatformPlayer? player;
  final _LeaderboardSnapshot? global;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFC73D).withValues(alpha: .16),
            const Color(0xFF7A5CFF).withValues(alpha: .12),
            const Color(0xFF0A1728).withValues(alpha: .98),
          ],
        ),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: const Color(0xFFFFC73D).withValues(alpha: .46),
        ),
      ),
      child: Row(
        children: [
          const DuelAssetIcon(DuelAsset.leaderboardCrownPro, size: 88),
          const SizedBox(width: 10),
          PlayerAvatar(
            displayName: name,
            avatarKey: 'leaderboards-$name',
            localAvatarBytes: player?.avatarBytes,
            remoteApprovedImageUrl: player?.avatarUrl,
            radius: 30,
            semanticLabel: context.tr(
              'player_avatar_semantics',
              <Object>[name],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
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
                  platformName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB7A9FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    _HeroValue(
                      label: context.tr('rank'),
                      value: global?.rank == null ? '—' : '#${global!.rank}',
                    ),
                    const SizedBox(width: 14),
                    _HeroValue(
                      label: context.tr('current_elo'),
                      value: '${global?.rating ?? 1000}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroValue extends StatelessWidget {
  const _HeroValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFFFC73D),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .5),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.label,
    required this.platformName,
    required this.snapshot,
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final String platformName;
  final _LeaderboardSnapshot? snapshot;
  final Color accent;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rank = snapshot?.rank;
    final neighbors = snapshot?.nearby.take(2).toList() ?? const <_NearbyPlayer>[];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(19),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: .16),
                const Color(0xFF0A1728).withValues(alpha: .98),
              ],
            ),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: accent.withValues(alpha: .45)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .07),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 37,
                    height: 37,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07111E).withValues(alpha: .65),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const DuelAssetIcon(
                      DuelAsset.leaderboardCrownPro,
                      size: 31,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    color: accent,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    rank == null ? '—' : '#$rank',
                    style: TextStyle(
                      color: accent,
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${context.tr('current_elo')}: ${snapshot?.rating ?? 1000}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (neighbors.isNotEmpty)
                Row(
                  children: [
                    for (var index = 0; index < neighbors.length; index++) ...[
                      Expanded(
                        child: Text(
                          '#${neighbors[index].rank} ${neighbors[index].name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .48),
                            fontSize: 9,
                          ),
                        ),
                      ),
                      if (index != neighbors.length - 1)
                        const SizedBox(width: 6),
                    ],
                  ],
                )
              else
                Text(
                  platformName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .43),
                    fontSize: 9,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardSnapshot {
  const _LeaderboardSnapshot({
    required this.rank,
    required this.rating,
    required this.nearby,
  });

  final int? rank;
  final int rating;
  final List<_NearbyPlayer> nearby;

  factory _LeaderboardSnapshot.fromJson(Map<String, dynamic> json) {
    final current = (json['currentPlayer'] as Map?)?.cast<String, dynamic>();
    final values = (json['entries'] as List?) ?? const <Object?>[];
    return _LeaderboardSnapshot(
      rank: (current?['rank'] as num?)?.toInt(),
      rating: (current?['rating'] as num?)?.toInt() ?? 1000,
      nearby: values
          .whereType<Map>()
          .map((raw) {
            final value = raw.cast<String, dynamic>();
            return _NearbyPlayer(
              rank: (value['rank'] as num?)?.toInt() ?? 0,
              name: value['displayName']?.toString() ?? 'Player',
            );
          })
          .where((player) => player.rank > 0)
          .toList(growable: false),
    );
  }
}

class _NearbyPlayer {
  const _NearbyPlayer({required this.rank, required this.name});

  final int rank;
  final String name;
}

String _scopeKey(PlatformLeaderboardScope scope) => switch (scope) {
  PlatformLeaderboardScope.global => 'global',
  _ => scope.name,
};

String _scopeLabel(BuildContext context, PlatformLeaderboardScope scope) {
  if (scope == PlatformLeaderboardScope.global) return context.tr('global_elo');
  final difficulty = SudokuDifficulty.values.firstWhere(
    (value) => value.name == scope.name,
  );
  return context.strings.difficultyLabel(difficulty);
}

Color _scopeColor(PlatformLeaderboardScope scope) => switch (scope) {
  PlatformLeaderboardScope.global => const Color(0xFFFFC73D),
  PlatformLeaderboardScope.beginner => const Color(0xFF35D2FF),
  PlatformLeaderboardScope.easy => const Color(0xFF29D398),
  PlatformLeaderboardScope.medium => const Color(0xFF7A5CFF),
  PlatformLeaderboardScope.hard => const Color(0xFFFF8C42),
  PlatformLeaderboardScope.expert => const Color(0xFFFF5868),
};
