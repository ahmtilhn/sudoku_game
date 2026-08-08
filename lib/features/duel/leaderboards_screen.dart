import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
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

  final PlatformGameServices _games = PlatformGameServices.instance;

  bool _loading = true;
  bool _openingNative = false;
  PlatformLeaderboardScope _selectedScope = PlatformLeaderboardScope.global;

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
      });
    }
    try {
      if (!await _games.isConfigured()) return;
      final authenticated = await _games.refreshAuthentication();
      if (authenticated && _games.localPlayer.value == null) {
        _games.localPlayer.value = await _games.getLocalPlayer();
      }
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      debugPrint('Leaderboard load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNative(PlatformLeaderboardScope scope) async {
    if (_openingNative) return;
    setState(() => _openingNative = true);
    try {
      final platform = kIsWeb ? null : defaultTargetPlatform;
      final leaderboardId = platform == null
          ? null
          : const PlatformLeaderboardIds().idFor(platform, scope);
      var opened = false;
      if (leaderboardId != null && await _games.isConfigured()) {
        var authenticated = await _games.refreshAuthentication();
        if (!authenticated) {
          authenticated = await _games.authenticate(notifyAccountBridge: false);
        }
        if (authenticated) {
          opened = await _games.showLeaderboard(leaderboardId: leaderboardId);
        }
      }
      debugPrint('Native leaderboard ${scope.name} opened=$opened');
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
      debugPrint('Native leaderboard ${scope.name} failed: $error');
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
    final name = platformPlayer?.displayName ?? 'Sudoku Player';
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return ListView(
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            _SelectedLeaderboardPanel(
              label: _scopeLabel(context, _selectedScope),
              scopeName: _scopeSubtitle(context, _selectedScope),
              platformName: platformName,
              accent: _scopeColor(_selectedScope),
              busy: _openingNative,
              onOpen: () => _openNative(_selectedScope),
            ),
            const SizedBox(height: 10),
            if (compact)
              for (final scope in _scopes) ...[
                _LeaderboardRow(
                  label: _scopeLabel(context, scope),
                  subtitle: _scopeSubtitle(context, scope),
                  accent: _scopeColor(scope),
                  selected: scope == _selectedScope,
                  busy: _openingNative,
                  onSelect: () => setState(() => _selectedScope = scope),
                  onOpen: () => _openNative(scope),
                ),
                const SizedBox(height: 8),
              ]
            else
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (final scope in _scopes)
                    SizedBox(
                      width: (constraints.maxWidth - 18) / 3,
                      child: _LeaderboardRow(
                        label: _scopeLabel(context, scope),
                        subtitle: _scopeSubtitle(context, scope),
                        accent: _scopeColor(scope),
                        selected: scope == _selectedScope,
                        busy: _openingNative,
                        onSelect: () => setState(() => _selectedScope = scope),
                        onOpen: () => _openNative(scope),
                      ),
                    ),
                ],
              ),
          ],
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
  });

  final String name;
  final String platformName;
  final PlatformPlayer? player;

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
          _PlatformAvatarBadge(
            name: name,
            player: player,
            platformName: platformName,
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
                    _HeroValue(label: context.tr('current_elo'), value: 'ELO'),
                    const SizedBox(width: 14),
                    _HeroValue(label: context.tr('leaderboards'), value: '6'),
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

class _PlatformAvatarBadge extends StatelessWidget {
  const _PlatformAvatarBadge({
    required this.name,
    required this.player,
    required this.platformName,
  });

  final String name;
  final PlatformPlayer? player;
  final String platformName;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        player?.avatarBytes != null ||
        (player?.avatarUrl?.trim().isNotEmpty ?? false);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: hasImage
                  ? const Color(0xFF29D398)
                  : Colors.white.withValues(alpha: .22),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF29D398).withValues(
                  alpha: hasImage ? .24 : 0,
                ),
                blurRadius: 18,
              ),
            ],
          ),
          child: PlayerAvatar(
            displayName: name,
            avatarKey: 'leaderboards-google-play-$name',
            localAvatarBytes: player?.avatarBytes,
            remoteApprovedImageUrl: player?.avatarUrl,
            radius: 31,
            semanticLabel: context.tr('player_avatar_semantics', <Object>[
              name,
            ]),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Tooltip(
            message: platformName,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: hasImage
                    ? const Color(0xFF29D398)
                    : const Color(0xFF7A8496),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF07111E), width: 2),
              ),
              child: const Icon(
                Icons.sports_esports_rounded,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectedLeaderboardPanel extends StatelessWidget {
  const _SelectedLeaderboardPanel({
    required this.label,
    required this.scopeName,
    required this.platformName,
    required this.accent,
    required this.busy,
    required this.onOpen,
  });

  final String label;
  final String scopeName;
  final String platformName;
  final Color accent;
  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const DuelAssetIcon(
              DuelAsset.leaderboardCrownPro,
              size: 42,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$scopeName · $platformName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .62),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: busy ? null : onOpen,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF07111E),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(
              context.tr('continue_action'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onOpen,
  });

  final String label;
  final String subtitle;
  final Color accent;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? accent
        : Colors.white.withValues(alpha: .11);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: .14)
                : const Color(0xFF0A1728).withValues(alpha: .72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: selected ? .2 : .11),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    _scopeMark(label),
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected ? context.tr('current_elo') : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .52),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('leaderboards'),
                onPressed: busy ? null : onOpen,
                style: IconButton.styleFrom(
                  foregroundColor: accent,
                  fixedSize: const Size(38, 38),
                  padding: EdgeInsets.zero,
                ),
                icon: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.open_in_new_rounded,
                  color: accent,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _scopeSubtitle(BuildContext context, PlatformLeaderboardScope scope) {
  return scope == PlatformLeaderboardScope.global
      ? context.tr('current_elo')
      : 'ELO';
}

String _scopeMark(String label) {
  final parts = label
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

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
