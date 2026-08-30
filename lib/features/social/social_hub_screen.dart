import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import 'package:flutter/services.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/player_profile_service.dart';
import '../../services/rank_identity_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/player_avatar.dart';
import 'challenge_waiting_screen.dart';
import 'ux_challenge_invitation_screen.dart';

class SocialHubScreen extends StatefulWidget {
  const SocialHubScreen({super.key});

  @override
  State<SocialHubScreen> createState() => _SocialHubScreenState();
}

class _SocialHubScreenState extends State<SocialHubScreen>
    with SingleTickerProviderStateMixin {
  final SocialApiClient _social = SocialApiClient.instance;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final TabController _tabs;

  PlayerProfilePreferences? _me;
  List<SocialPlayer> _friends = const [];
  List<SocialPlayer> _requests = const [];
  List<SocialPlayer> _opponents = const [];
  List<SocialChallenge> _challenges = const [];
  List<SocialPlayer> _results = const [];
  final Map<String, PublicRankSummary> _rankSummaries = {};
  final Set<String> _rankRequests = {};
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<SocialChallenge> get _incoming {
    final id = _me?.publicId;
    return _challenges
        .where((c) => c.status == 'pending' && c.recipient.publicId == id)
        .toList(growable: false);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait<Object>([
        PlayerProfileService.instance.load(),
        _social.loadFriends(),
        _social.loadIncomingFriendRequests(),
        _social.loadPendingChallenges(),
        _social.loadRecentOpponents(),
      ]);
      if (!mounted) return;
      final friends = values[1] as List<SocialPlayer>;
      final requests = values[2] as List<SocialPlayer>;
      final challenges = values[3] as List<SocialChallenge>;
      final opponents = values[4] as List<SocialPlayer>;
      setState(() {
        _me = values[0] as PlayerProfilePreferences;
        _friends = friends;
        _requests = requests;
        _challenges = challenges;
        _opponents = opponents;
      });
      unawaited(
        _loadRankSummaries([
          ...friends,
          ...requests,
          ...opponents,
          for (final c in challenges) c.challenger,
          for (final c in challenges) c.recipient,
        ]),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRankSummaries(Iterable<SocialPlayer> players) async {
    final pending = <SocialPlayer>[];
    for (final player in players) {
      final id = player.publicId.trim();
      if (id.length < 3 ||
          _rankSummaries.containsKey(id) ||
          _rankRequests.contains(id)) {
        continue;
      }
      _rankRequests.add(id);
      pending.add(player);
    }
    final loaded = await Future.wait(
      pending.map((player) async {
        final id = player.publicId.trim();
        try {
          return MapEntry(
            id,
            await RankIdentityService.instance.loadPublicRankSummary(id),
          );
        } catch (_) {
          return null;
        } finally {
          _rankRequests.remove(id);
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final entry in loaded) {
        if (entry != null) {
          _rankSummaries[entry.key] = entry.value;
        }
      }
    });
  }

  PublicRankSummary? _rankFor(String id) => _rankSummaries[id.trim()];

  Future<void> _perform(String id, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await action();
      await _load();
      if (_search.text.trim().length >= 3) {
        await _findPlayers();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _findPlayers() async {
    final query = _search.text.trim();
    if (query.length < 3 || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _social.searchPlayers(query);
      if (!mounted) return;
      setState(() => _results = results);
      unawaited(_loadRankSummaries(results));
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendFriendRequest(SocialPlayer player) async {
    if (!_canAdd(player)) return;
    await _perform(
      'friend-${player.publicId}',
      () => _social.sendFriendRequest(player.publicId),
    );
    if (mounted && _error == null) _snack(context.tr('friend_request_sent'));
  }

  Future<void> _respondRequest(SocialPlayer player, bool accept) async {
    await _perform(
      'request-${player.publicId}',
      () => _social.respondToFriendRequest(
        requesterPublicId: player.publicId,
        accept: accept,
      ),
    );
    if (mounted && _error == null && accept) {
      _snack(
        context.tr('friend_request_accepted', <Object>[player.displayName]),
      );
    }
  }

  Future<void> _challenge(SocialPlayer player) async {
    if (_busyId != null) return;
    final difficulty = await showModalBottomSheet<SudokuDifficulty>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0A1721),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('choose_duel_difficulty'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final item in SudokuDifficulty.values)
              ListTile(
                leading: const Icon(Icons.grid_4x4_rounded),
                title: Text(context.strings.difficultyLabel(item)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(sheetContext).pop(item),
              ),
          ],
        ),
      ),
    );
    if (difficulty == null || !mounted) return;
    setState(() {
      _busyId = 'challenge-${player.publicId}';
      _error = null;
    });
    try {
      final challenge = await _social.createChallenge(
        recipientPublicId: player.publicId,
        difficulty: difficulty.name,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChallengeWaitingScreen(challenge: challenge),
        ),
      );
      if (mounted) await _load();
    } on SocialApiException catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openChallenge(SocialChallenge challenge) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UxChallengeInvitationScreen(challengeId: challenge.id),
      ),
    );
    if (mounted) await _load();
  }

  bool _isIncomingRequest(SocialPlayer p) =>
      p.friendshipStatus == 'incoming_pending';

  bool _canAdd(SocialPlayer p) =>
      p.friendshipStatus != 'accepted' &&
      p.friendshipStatus != 'pending' &&
      p.friendshipStatus != 'outgoing_pending' &&
      p.friendshipStatus != 'incoming_pending';

  String _friendBusyId(SocialPlayer p) =>
      _isIncomingRequest(p) ? 'request-${p.publicId}' : 'friend-${p.publicId}';

  String _friendLabel(SocialPlayer p) {
    if (p.friendshipStatus == 'accepted') return context.tr('friends');
    if (_isIncomingRequest(p)) return context.tr('accept');
    if (!_canAdd(p)) return context.tr('friend_request_sent');
    return context.tr('add_friend');
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _showPlayer(
    SocialPlayer player, {
    String? primaryLabel,
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) async {
    final rank = _rankFor(player.publicId);
    final games = rank?.gamesPlayed ?? player.gamesPlayed;
    final wins = rank?.wins ?? player.wins;
    final winRate = rank?.winRate ?? player.winRate;
    final accent = _rankAccent(rank?.rankKey);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .80,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withValues(alpha: .14),
                const Color(0xFF0A1721),
                const Color(0xFF061019),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: accent.withValues(alpha: .32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                PlayerAvatar(
                  displayName: player.displayName,
                  avatarKey: rank?.avatarKey ?? 'detail-${player.publicId}',
                  radius: 50,
                ),
                const SizedBox(height: 10),
                Text(
                  player.displayName,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '@${player.username}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .48),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _Pill(rank?.rankName ?? context.tr('unranked'), accent),
                    _Pill(
                      context.tr('rp_value', <Object>[rank?.rankPoints ?? 0]),
                      const Color(0xFF66C7FF),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        context.tr('games_label'),
                        '$games',
                        Icons.sports_esports_rounded,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _Stat(
                        context.tr('wins_label'),
                        '$wins',
                        Icons.emoji_events_rounded,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _Stat(
                        context.tr('win_rate'),
                        '${(winRate * 100).round()}%',
                        Icons.percent_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        context.tr('losses'),
                        '${rank?.losses ?? (games - wins).clamp(0, games)}',
                        Icons.close_rounded,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _Stat(
                        context.tr('draws'),
                        '${rank?.draws ?? 0}',
                        Icons.drag_handle_rounded,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _Stat(
                        context.tr('achievement_label'),
                        '${player.achievementCount}',
                        Icons.workspace_premium_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.badge_outlined,
                  label: context.tr('friend_id'),
                  value: player.publicId,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: player.publicId));
                    _snack(context.tr('friend_id_copied'));
                  },
                ),
                if (player.lastPlayedAt != null) ...[
                  const SizedBox(height: 7),
                  _InfoRow(
                    icon: Icons.schedule_rounded,
                    label: context.tr('last_played'),
                    value: _lastPlayed(player.lastPlayedAt),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .035),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFFFC94D),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr('achievement_label'),
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '${player.achievementCount}',
                        style: const TextStyle(
                          color: Color(0xFFFFC94D),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                if (primaryLabel != null || secondaryLabel != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (secondaryLabel != null && onSecondary != null) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              onSecondary();
                            },
                            child: Text(secondaryLabel),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (primaryLabel != null)
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: onPrimary == null
                                ? null
                                : () {
                                    Navigator.of(sheetContext).pop();
                                    onPrimary();
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF29D398),
                              foregroundColor: const Color(0xFF07111E),
                              minimumSize: const Size.fromHeight(48),
                            ),
                            icon: Icon(_actionIcon(primaryLabel)),
                            label: Text(primaryLabel),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Column(
                      children: [
                        InPageHeader(
                          title: context.tr('friends_challenges'),
                          actions: [
                            IconButton(
                              tooltip: context.tr('refresh'),
                              onPressed: _loading ? null : _load,
                              icon: _loading
                                  ? const SizedBox.square(
                                      dimension: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _FixedTabs(
                          controller: _tabs,
                          requests: _requests.length,
                          friends: _friends.length,
                          challenges: _incoming.length,
                        ),
                        const SizedBox(height: 10),
                        _SearchField(
                          controller: _search,
                          focusNode: _searchFocus,
                          searching: _searching,
                          hasResults: _results.isNotEmpty,
                          onSearch: _findPlayers,
                          onClear: () {
                            _search.clear();
                            setState(() => _results = const []);
                          },
                        ),
                        if (_results.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: _panelDecoration(),
                            child: Column(
                              children: [
                                for (final p in _results.take(5)) ...[
                                  _SearchPlayer(
                                    player: p,
                                    rank: _rankFor(p.publicId),
                                    busy: _busyId == _friendBusyId(p),
                                    enabled:
                                        _isIncomingRequest(p) || _canAdd(p),
                                    label: _friendLabel(p),
                                    onTap: () => _showPlayer(
                                      p,
                                      primaryLabel: _friendLabel(p),
                                      onPrimary: _isIncomingRequest(p)
                                          ? () => _respondRequest(p, true)
                                          : _canAdd(p)
                                          ? () => _sendFriendRequest(p)
                                          : null,
                                      secondaryLabel: _isIncomingRequest(p)
                                          ? context.tr('decline')
                                          : null,
                                      onSecondary: _isIncomingRequest(p)
                                          ? () => _respondRequest(p, false)
                                          : null,
                                    ),
                                    onAction: _isIncomingRequest(p)
                                        ? () => _respondRequest(p, true)
                                        : () => _sendFriendRequest(p),
                                  ),
                                  const SizedBox(height: 5),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          _ErrorBar(
                            message: _error!,
                            onDismiss: () => setState(() => _error = null),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _requestsView(),
                          _friendsView(),
                          _challengesView(),
                          _recentView(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestsView() {
    if (_requests.isEmpty) {
      return _Empty(
        asset: DuelAsset.homeFriendsScene,
        title: context.tr('all_caught_up'),
        message: context.tr('friend_requests_empty'),
        action: context.tr('find_players'),
        onAction: _searchFocus.requestFocus,
      );
    }
    return _list([
      for (final p in _requests)
        _PlayerCard(
          player: p,
          rank: _rankFor(p.publicId),
          busy: _busyId == 'request-${p.publicId}',
          primary: context.tr('accept'),
          secondary: context.tr('decline'),
          onTap: () => _showPlayer(
            p,
            primaryLabel: context.tr('accept'),
            onPrimary: () => _respondRequest(p, true),
            secondaryLabel: context.tr('decline'),
            onSecondary: () => _respondRequest(p, false),
          ),
          onPrimary: () => _respondRequest(p, true),
          onSecondary: () => _respondRequest(p, false),
        ),
    ]);
  }

  Widget _friendsView() {
    if (_friends.isEmpty) {
      return _Empty(
        asset: DuelAsset.homeFriendsScene,
        title: context.tr('no_friends_yet'),
        message: context.tr('no_friends_body'),
        action: context.tr('find_friends'),
        onAction: _searchFocus.requestFocus,
      );
    }
    return _list([
      for (final p in _friends)
        _PlayerCard(
          player: p,
          rank: _rankFor(p.publicId),
          busy: _busyId == 'challenge-${p.publicId}',
          primary: context.tr('challenge'),
          onTap: () => _showPlayer(
            p,
            primaryLabel: context.tr('challenge'),
            onPrimary: () => _challenge(p),
          ),
          onPrimary: () => _challenge(p),
        ),
    ]);
  }

  Widget _recentView() {
    if (_opponents.isEmpty) {
      return _Empty(
        asset: DuelAsset.homeDuelScene,
        title: context.tr('no_recent_opponents'),
        message: context.tr('recent_opponents_empty_body'),
      );
    }
    return _list([
      for (final p in _opponents)
        _PlayerCard(
          player: p,
          rank: _rankFor(p.publicId),
          busy: _busyId == _friendBusyId(p),
          enabled: _isIncomingRequest(p) || _canAdd(p),
          primary: _friendLabel(p),
          secondary: _isIncomingRequest(p) ? context.tr('decline') : null,
          meta: _lastPlayed(p.lastPlayedAt),
          onTap: () => _showPlayer(
            p,
            primaryLabel: _friendLabel(p),
            onPrimary: _isIncomingRequest(p)
                ? () => _respondRequest(p, true)
                : _canAdd(p)
                ? () => _sendFriendRequest(p)
                : null,
            secondaryLabel: _isIncomingRequest(p)
                ? context.tr('decline')
                : null,
            onSecondary: _isIncomingRequest(p)
                ? () => _respondRequest(p, false)
                : null,
          ),
          onPrimary: _isIncomingRequest(p)
              ? () => _respondRequest(p, true)
              : () => _sendFriendRequest(p),
          onSecondary: _isIncomingRequest(p)
              ? () => _respondRequest(p, false)
              : null,
        ),
    ]);
  }

  Widget _challengesView() {
    if (_incoming.isEmpty) {
      return _Empty(
        asset: DuelAsset.homeDuelScene,
        title: context.tr('no_active_challenges'),
        message: context.tr('incoming_challenges_body'),
      );
    }
    return _list([
      for (final c in _incoming)
        _ChallengeCard(
          challenge: c,
          rank: _rankFor(c.challenger.publicId),
          onPlayer: () => _showPlayer(
            c.challenger,
            primaryLabel: context.tr('view_challenge'),
            onPrimary: () => _openChallenge(c),
          ),
          onOpen: () => _openChallenge(c),
        ),
    ]);
  }

  Widget _list(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => children[i],
      ),
    ),
  );
}

class _FixedTabs extends StatelessWidget {
  const _FixedTabs({
    required this.controller,
    required this.requests,
    required this.friends,
    required this.challenges,
  });
  final TabController controller;
  final int requests;
  final int friends;
  final int challenges;

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFF08141D).withValues(alpha: .90),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: Colors.white10),
    ),
    child: TabBar(
      controller: controller,
      isScrollable: false,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: const Color(0xFF29D398).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF35D5A1).withValues(alpha: .48),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF35D5A1).withValues(alpha: .14),
            blurRadius: 14,
          ),
        ],
      ),
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white54,
      labelPadding: EdgeInsets.zero,
      tabs: [
        _TabItem(Icons.group_add_rounded, 'Requests', requests),
        _TabItem(Icons.group_rounded, 'Friends', friends),
        _TabItem(Icons.sports_martial_arts_rounded, 'Challenges', challenges),
        const _TabItem(Icons.history_rounded, 'Recent', null),
      ],
    ),
  );
}

class _TabItem extends StatelessWidget {
  const _TabItem(this.icon, this.label, this.count);
  final IconData icon;
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) => Tab(
    height: 54,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            if (count != null) ...[
              const SizedBox(width: 4),
              Container(
                height: 18,
                constraints: const BoxConstraints(minWidth: 18),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF29D398).withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.hasResults,
    required this.onSearch,
    required this.onClear,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final bool hasResults;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      color: const Color(0xFF07131C).withValues(alpha: .80),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.white10),
    ),
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: !searching,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: context.tr('search_username_friend_id'),
        hintStyle: const TextStyle(fontSize: 12),
        border: InputBorder.none,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(13),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                onPressed: hasResults ? onClear : onSearch,
                icon: Icon(
                  hasResults
                      ? Icons.close_rounded
                      : Icons.arrow_forward_rounded,
                ),
              ),
      ),
      onSubmitted: (_) => onSearch(),
    ),
  );
}

class _SearchPlayer extends StatelessWidget {
  const _SearchPlayer({
    required this.player,
    required this.rank,
    required this.busy,
    required this.enabled,
    required this.label,
    required this.onTap,
    required this.onAction,
  });
  final SocialPlayer player;
  final PublicRankSummary? rank;
  final bool busy;
  final bool enabled;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Row(
          children: [
            PlayerAvatar(
              displayName: player.displayName,
              avatarKey: rank?.avatarKey ?? 'search-${player.publicId}',
              radius: 21,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    rank == null
                        ? '@${player.username}'
                        : context.tr('rank_points_format', <Object>[
                            rank!.rankName,
                            rank!.rankPoints,
                          ]),
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: busy || !enabled ? null : onAction,
              child: busy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.rank,
    required this.busy,
    required this.primary,
    required this.onTap,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.enabled = true,
    this.meta,
  });
  final SocialPlayer player;
  final PublicRankSummary? rank;
  final bool busy;
  final bool enabled;
  final String primary;
  final String? secondary;
  final String? meta;
  final VoidCallback onTap;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final accent = _rankAccent(rank?.rankKey);
    final winRate = rank?.winRate ?? player.winRate;
    final games = rank?.gamesPlayed ?? player.gamesPlayed;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: .08),
            const Color(0xFF07131C).withValues(alpha: .90),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Row(
                  children: [
                    PlayerAvatar(
                      displayName: player.displayName,
                      avatarKey: rank?.avatarKey ?? 'player-${player.publicId}',
                      radius: 27,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            player.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@${player.username}${rank == null ? '' : ' · ${rank!.rankName}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 8,
                            children: [
                              _Meta(
                                Icons.shield_rounded,
                                '${rank?.rankPoints ?? 0} RP',
                                accent,
                              ),
                              _Meta(
                                Icons.emoji_events_rounded,
                                '${(winRate * 100).round()}%',
                                const Color(0xFFFFC94D),
                              ),
                              _Meta(
                                Icons.sports_esports_rounded,
                                '$games',
                                const Color(0xFF66C7FF),
                              ),
                              if (meta != null && meta!.isNotEmpty)
                                _Meta(
                                  Icons.schedule_rounded,
                                  meta!,
                                  Colors.white54,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          if (secondary != null && onSecondary != null) ...[
            TextButton(
              onPressed: busy ? null : onSecondary,
              child: Text(secondary!),
            ),
            const SizedBox(width: 3),
          ],
          FilledButton.tonal(
            onPressed: busy || !enabled ? null : onPrimary,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF29D398).withValues(alpha: .12),
              side: BorderSide(
                color: const Color(0xFF29D398).withValues(alpha: .34),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13),
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    primary,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.rank,
    required this.onPlayer,
    required this.onOpen,
  });
  final SocialChallenge challenge;
  final PublicRankSummary? rank;
  final VoidCallback onPlayer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFFFF8A4C).withValues(alpha: .10),
          const Color(0xFF07131C).withValues(alpha: .90),
        ],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFFFA15A).withValues(alpha: .30)),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onPlayer,
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                PlayerAvatar(
                  displayName: challenge.challenger.displayName,
                  avatarKey:
                      rank?.avatarKey ??
                      'challenge-${challenge.challenger.publicId}',
                  radius: 27,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.challenger.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        rank == null
                            ? '@${challenge.challenger.username}'
                            : context.tr('rank_points_format', <Object>[
                                rank!.rankName,
                                rank!.rankPoints,
                              ]),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        children: [
                          _Meta(
                            Icons.grid_4x4_rounded,
                            context.strings.difficultyLabel(
                              _difficulty(challenge.difficulty),
                            ),
                            const Color(0xFFFFB46A),
                          ),
                          _Meta(
                            Icons.schedule_rounded,
                            _expires(challenge.expiresAt),
                            const Color(0xFF66C7FF),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: onOpen,
          icon: const Icon(Icons.sports_martial_arts_rounded, size: 16),
          label: Text(context.tr('view')),
        ),
      ],
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text(
        text,
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: .30)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .035),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(
      children: [
        Icon(icon, size: 17, color: const Color(0xFF66C7FF)),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 8.5),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .03),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white10),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Colors.white54),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (onTap != null)
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.asset,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });
  final String asset;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF123149).withValues(alpha: .34),
                const Color(0xFF07131C).withValues(alpha: .76),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 105,
                height: 105,
                child: DuelAssetIcon(asset, size: 100, fit: BoxFit.contain),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              if (action != null && onAction != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF29D398),
                      foregroundColor: const Color(0xFF07111E),
                    ),
                    icon: const Icon(Icons.person_search_rounded),
                    label: Text(action!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFF6B6B).withValues(alpha: .09),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: .24)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFFF8D8D),
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        ),
        IconButton(
          onPressed: onDismiss,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  );
}

BoxDecoration _panelDecoration() => BoxDecoration(
  color: const Color(0xFF07131C).withValues(alpha: .90),
  borderRadius: BorderRadius.circular(17),
  border: Border.all(color: const Color(0xFF35D5A1).withValues(alpha: .18)),
);

Color _rankAccent(String? rankKey) {
  final key = rankKey?.toLowerCase() ?? '';
  if (key.startsWith('silver')) return const Color(0xFFB9CAD8);
  if (key.startsWith('gold')) return const Color(0xFFFFC84D);
  if (key.startsWith('platinum')) return const Color(0xFF63DCF3);
  if (key.startsWith('master')) return const Color(0xFFC587FF);
  return const Color(0xFFE49555);
}

String _lastPlayed(DateTime? value) {
  if (value == null) return '';
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.isNegative || diff.inMinutes < 1) return 'Now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${value.toLocal().day}/${value.toLocal().month}';
}

String _expires(DateTime value) {
  final diff = value.toLocal().difference(DateTime.now());
  if (diff.isNegative) return 'Expiring';
  if (diff.inMinutes < 1) return '<1m';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  return '${diff.inHours}h';
}

IconData _actionIcon(String label) {
  final value = label.toLowerCase();
  if (value.contains('add')) return Icons.person_add_alt_1_rounded;
  if (value.contains('accept')) return Icons.check_rounded;
  if (value.contains('friend')) return Icons.group_rounded;
  return Icons.sports_martial_arts_rounded;
}

SudokuDifficulty _difficulty(String value) =>
    SudokuDifficulty.values.firstWhere(
      (difficulty) => difficulty.name == value,
      orElse: () => SudokuDifficulty.easy,
    );
