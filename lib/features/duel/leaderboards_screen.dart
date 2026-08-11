import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../domain/sudoku_variant.dart';
import '../../localization/app_strings.dart';
import '../../services/competitive_leaderboard_api.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/player_avatar.dart';

enum _LeaderboardAudience { world, friends, aroundMe }

class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen> {
  final CompetitiveLeaderboardApi _leaderboards =
      CompetitiveLeaderboardApi.instance;
  final PlatformGameServices _games = PlatformGameServices.instance;
  final PlatformLeaderboardService _platformLeaderboards =
      PlatformLeaderboardService.instance;
  final SocialApiClient _social = SocialApiClient.instance;

  SudokuVariant _variant = SudokuVariant.classic9;
  PlatformLeaderboardScope _selectedScope = PlatformLeaderboardScope.global;
  _LeaderboardAudience _audience = _LeaderboardAudience.world;
  List<CompetitiveLeaderboardEntry> _entries =
      const <CompetitiveLeaderboardEntry>[];
  CompetitiveLeaderboardCurrentPlayer? _currentPlayer;
  CompetitiveProfile? _profile;
  String? _nextCursor;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _openingNative = false;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _games.localPlayer.addListener(_refreshPlatformIdentity);
    unawaited(_loadIdentity());
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

  Future<void> _loadIdentity() async {
    try {
      if (await _games.isConfigured()) {
        final authenticated = await _games.refreshAuthentication();
        if (authenticated && _games.localPlayer.value == null) {
          _games.localPlayer.value = await _games.getLocalPlayer();
        }
      }
    } catch (error) {
      debugPrint('Leaderboard platform identity failed: $error');
    }

    try {
      if (_social.configured) {
        final profile = await _social.loadCompetitiveProfile();
        if (mounted) setState(() => _profile = profile);
      }
    } catch (error) {
      debugPrint('Leaderboard profile identity failed: $error');
    }
  }

  Future<void> _load({bool reset = true}) async {
    final requestId = ++_requestSerial;
    if (mounted) {
      setState(() {
        if (reset) {
          _loading = true;
          _entries = const <CompetitiveLeaderboardEntry>[];
          _nextCursor = null;
          _currentPlayer = null;
        } else {
          _loadingMore = true;
        }
        _error = null;
      });
    }

    try {
      final page = await _leaderboards.load(
        scope: _selectedScope.name,
        variant: _variant.key,
        mode: _modeFor(_audience),
        cursor: reset ? null : _nextCursor,
        limit: 50,
      );
      if (!mounted || requestId != _requestSerial) return;

      final incoming = page.entries;
      debugPrint(
        'Sudoku ELO leaderboard loaded: variant=${page.variant}, '
        'scope=${page.scope}, mode=${page.mode}, entries=${incoming.length}, '
        'currentGames=${page.currentPlayer.gamesPlayed}, '
        'currentRank=${page.currentPlayer.rank}',
      );
      setState(() {
        _entries = reset
            ? incoming
            : <CompetitiveLeaderboardEntry>[..._entries, ...incoming];
        _currentPlayer = page.currentPlayer;
        _nextCursor = page.nextCursor;
      });
    } catch (error) {
      if (!mounted || requestId != _requestSerial) return;
      debugPrint('Sudoku ELO leaderboard load failed: $error');
      setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted && requestId == _requestSerial) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _nextCursor == null) return;
    if (_audience != _LeaderboardAudience.world) return;
    await _load(reset: false);
  }

  void _selectVariant(SudokuVariant variant) {
    if (_variant == variant) return;
    setState(() => _variant = variant);
    unawaited(_load());
  }

  void _selectScope(PlatformLeaderboardScope scope) {
    if (_selectedScope == scope) return;
    setState(() => _selectedScope = scope);
    unawaited(_load());
  }

  void _selectAudience(_LeaderboardAudience audience) {
    if (_audience == audience) return;
    setState(() => _audience = audience);
    unawaited(_load());
  }

  int? _effectiveCurrentRank() {
    final current = _currentPlayer;
    if (current == null) return null;
    if (_audience != _LeaderboardAudience.friends) return current.rank;

    final publicId = _profile?.publicId;
    if (publicId == null || publicId.isEmpty) return null;
    for (final entry in _entries) {
      if (entry.publicId == publicId) return entry.rank;
    }
    return null;
  }

  Future<void> _openNative() async {
    if (_openingNative || _variant != SudokuVariant.classic9) return;
    setState(() => _openingNative = true);
    try {
      var opened = await _platformLeaderboards.show(_selectedScope);
      if (!opened && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        opened = await _games.showLeaderboard();
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

  Future<void> _showPlayerDetails(CompetitiveLeaderboardEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0A1728),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatar(
                displayName: entry.displayName,
                avatarKey: entry.avatarKey,
                radius: 34,
              ),
              const SizedBox(height: 10),
              Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (entry.username.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '@${entry.username}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _StatPill(
                    icon: Icons.emoji_events_rounded,
                    label: context.tr('rank'),
                    value: entry.isProvisional ? '—' : '#${entry.rank}',
                  ),
                  _StatPill(
                    icon: Icons.bolt_rounded,
                    label: context.tr('current_elo'),
                    value: '${entry.rating}',
                  ),
                  _StatPill(
                    icon: Icons.sports_esports_rounded,
                    label: context.tr('wins_losses_draws'),
                    value: '${entry.wins}/${entry.losses}/${entry.draws}',
                  ),
                  _StatPill(
                    icon: Icons.percent_rounded,
                    label: context.tr('win_rate'),
                    value: '${(entry.winRate * 100).round()}%',
                  ),
                  if (entry.winStreak > 0)
                    _StatPill(
                      icon: Icons.local_fire_department_rounded,
                      label: context.tr('win_streak'),
                      value: '${entry.winStreak}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platformPlayer = _games.localPlayer.value;
    final displayName = _profile?.displayName.trim().isNotEmpty == true
        ? _profile!.displayName
        : platformPlayer?.effectiveDisplayName ?? context.tr('you');
    final current = _currentPlayer;
    final currentRank = _effectiveCurrentRank();

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Column(
                  children: [
                    _Header(
                      busy: _loading,
                      nativeBusy: _openingNative,
                      showNative: _variant == SudokuVariant.classic9,
                      platformName: _platformName(),
                      onBack: () => Navigator.of(context).pop(),
                      onRefresh: () => _load(),
                      onNative: _openNative,
                    ),
                    const SizedBox(height: 10),
                    _Hero(
                      displayName: displayName,
                      player: platformPlayer,
                      rating: current?.rating,
                      rank: currentRank,
                      variantLabel: _variant.label,
                      scopeLabel: _scopeLabel(context, _selectedScope),
                    ),
                    const SizedBox(height: 10),
                    _Filters(
                      variant: _variant,
                      scope: _selectedScope,
                      audience: _audience,
                      onVariant: _selectVariant,
                      onScope: _selectScope,
                      onAudience: _selectAudience,
                    ),
                    const SizedBox(height: 10),
                    Expanded(child: _buildLeaderboardBody()),
                    if (!_loading && current != null) ...[
                      const SizedBox(height: 8),
                      _CurrentPlayerBar(
                        displayName: displayName,
                        player: platformPlayer,
                        rating: current.rating,
                        rank: currentRank,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _InlineState(
        icon: Icons.cloud_off_rounded,
        message: _error!,
        actionLabel: context.tr('try_again'),
        onAction: () => _load(),
      );
    }
    if (_entries.isEmpty) {
      final current = _currentPlayer;
      if (current != null && current.gamesPlayed > 0) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 6),
          children: [
            _CurrentOnlyCard(
              displayName: _profile?.displayName.trim().isNotEmpty == true
                  ? _profile!.displayName
                  : (_games.localPlayer.value?.effectiveDisplayName ??
                        context.tr('you')),
              player: _games.localPlayer.value,
              current: current,
              rank: _effectiveCurrentRank(),
            ),
          ],
        );
      }
      return _InlineState(
        icon: Icons.leaderboard_outlined,
        message:
            '${context.tr('leaderboard_empty')}\n${context.tr('leaderboard_empty_hint')}',
        actionLabel: context.tr('refresh'),
        onAction: () => _load(),
      );
    }

    final showPodium =
        _audience == _LeaderboardAudience.world &&
        _entries.length >= 3 &&
        _entries.take(3).every((entry) => !entry.isProvisional);
    final listStart = showPodium ? 3 : 0;

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 6),
        children: [
          _LeaderboardSummaryStrip(
            entries: _entries,
            current: _currentPlayer,
            currentRank: _effectiveCurrentRank(),
            audience: _audience,
          ),
          const SizedBox(height: 9),
          if (showPodium) ...[
            _Podium(entries: _entries.take(3).toList(growable: false)),
            const SizedBox(height: 9),
          ],
          for (final entry in _entries.skip(listStart)) ...[
            _LeaderboardEntryTile(
              entry: entry,
              onTap: () => _showPlayerDetails(entry),
            ),
            const SizedBox(height: 7),
          ],
          if (_audience == _LeaderboardAudience.world && _nextCursor != null)
            Center(
              child: FilledButton.tonalIcon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(context.tr('continue_action')),
              ),
            ),
        ],
      ),
    );
  }

  String _platformName() {
    if (kIsWeb) return context.tr('leaderboards');
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'Game Center'
        : 'Google Play Games';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.busy,
    required this.nativeBusy,
    required this.showNative,
    required this.platformName,
    required this.onBack,
    required this.onRefresh,
    required this.onNative,
  });

  final bool busy;
  final bool nativeBusy;
  final bool showNative;
  final String platformName;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onNative;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const SizedBox(width: 8),
          const DuelAssetIcon(DuelAsset.leaderboardCrownPro, size: 36),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('leaderboards'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Sudoku Duel ELO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .62),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (showNative) ...[
            Text(
              context.tr('native_leaderboard_short'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: .56),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            IconButton.filledTonal(
              tooltip: platformName,
              onPressed: nativeBusy ? null : onNative,
              icon: nativeBusy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sports_esports_rounded),
            ),
          ],
          const SizedBox(width: 5),
          IconButton.filledTonal(
            tooltip: context.tr('refresh'),
            onPressed: busy ? null : onRefresh,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
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
    required this.displayName,
    required this.player,
    required this.rating,
    required this.rank,
    required this.variantLabel,
    required this.scopeLabel,
  });

  final String displayName;
  final PlatformPlayer? player;
  final int? rating;
  final int? rank;
  final String variantLabel;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF66C7FF).withValues(alpha: .24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final values = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              _HeroValue(
                label: context.tr('current_elo'),
                value: rating == null ? '—' : '$rating',
                color: const Color(0xFF66C7FF),
              ),
              _HeroValue(
                label: context.tr('rank'),
                value: rank == null ? '—' : '#$rank',
                color: const Color(0xFFB7A9FF),
              ),
            ],
          );
          final identity = Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF66C7FF).withValues(alpha: .28),
                  ),
                ),
                child: PlayerAvatar(
                  displayName: displayName,
                  avatarKey: 'home-profile-leaderboard',
                  localAvatarBytes: player?.avatarBytes,
                  remoteApprovedImageUrl: player?.avatarUrl,
                  radius: 29,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
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
                      '$variantLabel · $scopeLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .64),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const SizedBox(height: 12), values],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              values,
            ],
          );
        },
      ),
    );
  }
}

class _HeroValue extends StatelessWidget {
  const _HeroValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .54),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.variant,
    required this.scope,
    required this.audience,
    required this.onVariant,
    required this.onScope,
    required this.onAudience,
  });

  final SudokuVariant variant;
  final PlatformLeaderboardScope scope;
  final _LeaderboardAudience audience;
  final ValueChanged<SudokuVariant> onVariant;
  final ValueChanged<PlatformLeaderboardScope> onScope;
  final ValueChanged<_LeaderboardAudience> onAudience;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<SudokuVariant>(
              segments: [
                ButtonSegment(
                  value: SudokuVariant.classic9,
                  label: Text(context.tr('classic_9x9')),
                  icon: const Icon(Icons.grid_3x3_rounded),
                ),
                ButtonSegment(
                  value: SudokuVariant.classic16,
                  label: Text(context.tr('classic_16x16')),
                  icon: const Icon(Icons.grid_4x4_rounded),
                ),
              ],
              selected: <SudokuVariant>{variant},
              showSelectedIcon: false,
              onSelectionChanged: (values) => onVariant(values.first),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _LeaderboardScreenData.scopes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final value = _LeaderboardScreenData.scopes[index];
                return ChoiceChip(
                  selected: scope == value,
                  label: Text(_scopeLabel(context, value)),
                  onSelected: (_) => onScope(value),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                );
              },
            ),
          ),
          const SizedBox(height: 9),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_LeaderboardAudience>(
              segments: [
                ButtonSegment(
                  value: _LeaderboardAudience.world,
                  label: Text(context.tr('world')),
                  icon: const Icon(Icons.public_rounded),
                ),
                ButtonSegment(
                  value: _LeaderboardAudience.friends,
                  label: Text(context.tr('friends')),
                  icon: const Icon(Icons.group_rounded),
                ),
                ButtonSegment(
                  value: _LeaderboardAudience.aroundMe,
                  label: Text(context.tr('you')),
                  icon: const Icon(Icons.my_location_rounded),
                ),
              ],
              selected: <_LeaderboardAudience>{audience},
              showSelectedIcon: false,
              onSelectionChanged: (values) => onAudience(values.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentOnlyCard extends StatelessWidget {
  const _CurrentOnlyCard({
    required this.displayName,
    required this.player,
    required this.current,
    required this.rank,
  });

  final String displayName;
  final PlatformPlayer? player;
  final CompetitiveLeaderboardCurrentPlayer current;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF29D398).withValues(alpha: .22),
        ),
      ),
      child: Row(
        children: [
          PlayerAvatar(
            displayName: displayName,
            avatarKey: 'leaderboard-current-only',
            localAvatarBytes: player?.avatarBytes,
            remoteApprovedImageUrl: player?.avatarUrl,
            radius: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${context.tr('wins_losses_draws')} '
                  '${current.wins}/${current.losses}/${current.draws}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rank == null ? '—' : '#$rank',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .58),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${current.rating}',
                style: const TextStyle(
                  color: Color(0xFF29D398),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeaderboardSummaryStrip extends StatelessWidget {
  const _LeaderboardSummaryStrip({
    required this.entries,
    required this.current,
    required this.currentRank,
    required this.audience,
  });

  final List<CompetitiveLeaderboardEntry> entries;
  final CompetitiveLeaderboardCurrentPlayer? current;
  final int? currentRank;
  final _LeaderboardAudience audience;

  @override
  Widget build(BuildContext context) {
    final top = entries.isEmpty ? null : entries.first;
    final audienceLabel = switch (audience) {
      _LeaderboardAudience.world => context.tr('world'),
      _LeaderboardAudience.friends => context.tr('friends'),
      _LeaderboardAudience.aroundMe => context.tr('you'),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .17),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final columns = compact ? 1 : 3;
            final width =
                (constraints.maxWidth - ((columns - 1) * 8)) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: width,
                  child: _SummaryCell(
                    label: context.tr('top_rank'),
                    value: top == null ? '-' : top.displayName,
                    detail: top == null
                        ? context.tr('no_score')
                        : context.tr('rating_value', <Object>[top.rating]),
                    asset: DuelAsset.leaderboardCrownPro,
                    color: const Color(0xFF66C7FF),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _SummaryCell(
                    label: context.tr('your_rank'),
                    value: currentRank == null ? '-' : '#$currentRank',
                    detail: current == null
                        ? context.tr('no_elo')
                        : context.tr('rating_value', <Object>[current!.rating]),
                    asset: DuelAsset.profilePro,
                    color: const Color(0xFFB7A9FF),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _SummaryCell(
                    label: context.tr('board'),
                    value: audienceLabel,
                    detail: context.tr('entries_shown', <Object>[
                      entries.length,
                    ]),
                    asset: DuelAsset.people,
                    color: const Color(0xFF29D398),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.detail,
    required this.asset,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .15)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: DuelAssetIcon(asset, size: 21, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$label · $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .56),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
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

class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  final List<CompetitiveLeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final ordered = <CompetitiveLeaderboardEntry>[
      entries[1],
      entries[0],
      entries[2],
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < ordered.length; index++) ...[
          Expanded(
            child: _PodiumCard(entry: ordered[index], elevated: index == 1),
          ),
          if (index != ordered.length - 1) const SizedBox(width: 7),
        ],
      ],
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({required this.entry, required this.elevated});

  final CompetitiveLeaderboardEntry entry;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final tier = _tierForRating(entry.rating);
    final accent = entry.rank == 1 ? const Color(0xFF66C7FF) : tier.color;
    return Container(
      padding: EdgeInsets.fromLTRB(10, elevated ? 16 : 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: elevated ? .34 : .23),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: .2)),
            ),
            child: Text(
              '#${entry.rank}',
              style: TextStyle(
                color: accent,
                fontSize: elevated ? 16 : 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _EloTierEmblem(
            rating: entry.rating,
            size: elevated ? 58 : 50,
            elevated: elevated,
          ),
          const SizedBox(height: 8),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${tier.label(context)} · ${context.tr('rating_value', <Object>[entry.rating])}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardEntryTile extends StatelessWidget {
  const _LeaderboardEntryTile({required this.entry, required this.onTap});

  final CompetitiveLeaderboardEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tier = _tierForRating(entry.rating);
    final accent = entry.rank <= 3 && !entry.isProvisional
        ? const Color(0xFF66C7FF)
        : tier.color;
    final winRate = '${(entry.winRate * 100).round()}%';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: accent.withValues(alpha: .18)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: .16)),
                ),
                child: entry.isProvisional
                    ? const Icon(
                        Icons.hourglass_top_rounded,
                        color: Color(0xFFB7A9FF),
                        size: 20,
                      )
                    : Text(
                        '#${entry.rank}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              _EloTierEmblem(rating: entry.rating, size: 46),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (entry.country != null) ...[
                          const SizedBox(width: 5),
                          Text(
                            entry.country!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .42),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tier.label(context)} · ${context.tr('wins_losses_draws')} ${entry.wins}/${entry.losses}/${entry.draws}'
                      '${entry.winStreak > 0 ? ' · Streak ${entry.winStreak}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .48),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entry.rating}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'ELO',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .42),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF29D398).withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF29D398).withValues(alpha: .16),
                      ),
                    ),
                    child: Text(
                      winRate,
                      style: const TextStyle(
                        color: Color(0xFF29D398),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EloTierData {
  const _EloTierData({
    required this.labelKey,
    required this.shortLabel,
    required this.color,
  });

  final String labelKey;
  final String shortLabel;
  final Color color;

  String label(BuildContext context) => context.tr(labelKey);
}

_EloTierData _tierForRating(int rating) {
  if (rating >= 2100) {
    return const _EloTierData(
      labelKey: 'tier_master',
      shortLabel: 'M',
      color: Color(0xFF29D398),
    );
  }
  if (rating >= 1800) {
    return const _EloTierData(
      labelKey: 'tier_diamond',
      shortLabel: 'D',
      color: Color(0xFFB7A9FF),
    );
  }
  if (rating >= 1600) {
    return const _EloTierData(
      labelKey: 'tier_platinum',
      shortLabel: 'P',
      color: Color(0xFF66C7FF),
    );
  }
  if (rating >= 1400) {
    return const _EloTierData(
      labelKey: 'tier_gold',
      shortLabel: 'G',
      color: Color(0xFFD1E889),
    );
  }
  if (rating >= 1200) {
    return const _EloTierData(
      labelKey: 'tier_silver',
      shortLabel: 'S',
      color: Color(0xFFC8D7E3),
    );
  }
  return const _EloTierData(
    labelKey: 'tier_bronze',
    shortLabel: 'B',
    color: Color(0xFF9AA7B2),
  );
}

class _EloTierEmblem extends StatelessWidget {
  const _EloTierEmblem({
    required this.rating,
    required this.size,
    this.elevated = false,
  });

  final int rating;
  final double size;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final tier = _tierForRating(rating);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: elevated ? .28 : .20),
        border: Border.all(
          color: tier.color.withValues(alpha: .36),
          width: 1.4,
        ),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: tier.color.withValues(alpha: .18),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Container(
          width: size - 10,
          height: size - 10,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tier.color.withValues(alpha: .12),
            border: Border.all(color: tier.color.withValues(alpha: .18)),
          ),
          child: Text(
            tier.shortLabel,
            style: TextStyle(
              color: tier.color,
              fontSize: size * .34,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentPlayerBar extends StatelessWidget {
  const _CurrentPlayerBar({
    required this.displayName,
    required this.player,
    required this.rating,
    required this.rank,
  });

  final String displayName;
  final PlatformPlayer? player;
  final int rating;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .30),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFF66C7FF).withValues(alpha: .28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          PlayerAvatar(
            displayName: displayName,
            avatarKey: 'home-profile-leaderboard-sticky',
            localAvatarBytes: player?.avatarBytes,
            remoteApprovedImageUrl: player?.avatarUrl,
            radius: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              context.tr('you'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            rank == null ? '—' : '#$rank',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .7),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '$rating ELO',
            style: const TextStyle(
              color: Color(0xFF66C7FF),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFB7A9FF), size: 16),
          const SizedBox(width: 6),
          Text(
            '$label $value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: .5), size: 42),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .68),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardScreenData {
  const _LeaderboardScreenData._();

  static const List<PlatformLeaderboardScope> scopes =
      <PlatformLeaderboardScope>[
        PlatformLeaderboardScope.global,
        PlatformLeaderboardScope.beginner,
        PlatformLeaderboardScope.easy,
        PlatformLeaderboardScope.medium,
        PlatformLeaderboardScope.hard,
        PlatformLeaderboardScope.expert,
      ];
}

String _modeFor(_LeaderboardAudience audience) => switch (audience) {
  _LeaderboardAudience.world => 'top',
  _LeaderboardAudience.friends => 'friends',
  _LeaderboardAudience.aroundMe => 'around_me',
};

String _scopeLabel(BuildContext context, PlatformLeaderboardScope scope) {
  if (scope == PlatformLeaderboardScope.global) return context.tr('global_elo');
  final difficulty = SudokuDifficulty.values.firstWhere(
    (value) => value.name == scope.name,
  );
  return context.strings.difficultyLabel(difficulty);
}
