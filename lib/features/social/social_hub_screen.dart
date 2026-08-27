import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/player_profile_service.dart';
import '../../services/rank_identity_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
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
  late final TabController _tabs;

  PlayerProfilePreferences? _me;
  List<SocialPlayer> _friends = const [];
  List<SocialPlayer> _requests = const [];
  List<SocialPlayer> _opponents = const [];
  List<SocialChallenge> _challenges = const [];
  List<SocialPlayer> _results = const [];
  final Map<String, PublicRankSummary> _rankSummaries =
      <String, PublicRankSummary>{};
  final Set<String> _rankRequests = <String>{};
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
    super.dispose();
  }

  List<SocialChallenge> get _incoming {
    final id = _me?.publicId;
    return _challenges
        .where(
          (challenge) =>
              challenge.status == 'pending' &&
              challenge.recipient.publicId == id,
        )
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
      final rankPlayers = <SocialPlayer>[
        ...friends,
        ...requests,
        ...opponents,
        for (final challenge in challenges) challenge.challenger,
        for (final challenge in challenges) challenge.recipient,
      ];
      unawaited(_loadRankSummaries(rankPlayers));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
    if (pending.isEmpty) return;

    final loaded = await Future.wait<MapEntry<String, PublicRankSummary>?>(
      pending.map((player) async {
        final id = player.publicId.trim();
        try {
          final summary = await RankIdentityService.instance
              .loadPublicRankSummary(id);
          return MapEntry<String, PublicRankSummary>(id, summary);
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
        if (entry != null) _rankSummaries[entry.key] = entry.value;
      }
    });
  }

  PublicRankSummary? _rankFor(String publicId) =>
      _rankSummaries[publicId.trim()];

  Future<void> _perform(String id, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
      if (mounted) {
        setState(() => _results = results);
        unawaited(_loadRankSummaries(results));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendFriendRequest(SocialPlayer player) async {
    if (player.friendshipStatus == 'accepted' ||
        player.friendshipStatus == 'pending') {
      return;
    }
    await _perform('friend-${player.publicId}', () async {
      await _social.sendFriendRequest(player.publicId);
    });
    if (!mounted || _error != null) return;
    _showSnack(context.tr('friend_request_sent'));
  }

  Future<void> _respondRequest(SocialPlayer player, bool accept) async {
    await _perform('request-${player.publicId}', () async {
      await _social.respondToFriendRequest(
        requesterPublicId: player.publicId,
        accept: accept,
      );
    });
    if (!mounted || _error != null || !accept) return;
    _showSnack(
      context.tr('friend_request_accepted', <Object>[player.displayName]),
    );
  }

  Future<void> _challenge(SocialPlayer player) async {
    if (_busyId != null) return;
    final difficulty = await showModalBottomSheet<SudokuDifficulty>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('choose_duel_difficulty'),
              textAlign: TextAlign.center,
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final item in SudokuDifficulty.values)
              ListTile(
                minTileHeight: 52,
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
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
    await _load();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      children: [
                        InPageHeader(
                          title: context.tr('friends_challenges'),
                          actions: [
                            IconButton(
                              tooltip: context.tr('refresh'),
                              onPressed: _loading ? null : _load,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        TabBar(
                          controller: _tabs,
                          isScrollable: true,
                          tabs: [
                            Tab(
                              text:
                                  '${context.tr('friend_requests')} (${_requests.length})',
                            ),
                            Tab(
                              text:
                                  '${context.tr('friends')} (${_friends.length})',
                            ),
                            Tab(
                              text:
                                  '${context.tr('challenge')} (${_incoming.length})',
                            ),
                            Tab(text: context.tr('recent_opponents')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _search,
                          enabled: !_searching,
                          textInputAction: TextInputAction.search,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText:
                                '${context.tr('unique_username')} / ${context.tr('friend_id')}',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: IconButton(
                              tooltip: context.tr('try_again'),
                              onPressed: _searching ? null : _findPlayers,
                              icon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                            ),
                          ),
                          onSubmitted: (_) => _findPlayers(),
                        ),
                        if (_results.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Card(
                            child: Column(
                              children: [
                                for (final player in _results.take(5))
                                  _PlayerRow(
                                    player: player,
                                    rank: _rankFor(player.publicId),
                                    busy:
                                        _busyId == 'friend-${player.publicId}',
                                    enabled:
                                        player.friendshipStatus != 'accepted' &&
                                        player.friendshipStatus != 'pending',
                                    primaryLabel:
                                        player.friendshipStatus == 'accepted'
                                        ? context.tr('friends')
                                        : player.friendshipStatus == 'pending'
                                        ? context.tr('friend_request_sent')
                                        : context.tr('add_friend'),
                                    onPrimary: () => _sendFriendRequest(player),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: ListTile(
                              leading: const Icon(Icons.error_outline),
                              title: Text(_error!),
                              trailing: IconButton(
                                tooltip: context.tr('dismiss'),
                                onPressed: () => setState(() => _error = null),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
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
                          _playersView(_friends),
                          _challengesView(),
                          _recentOpponentsView(),
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
      return _Empty(message: context.tr('friend_requests_empty'));
    }
    return _scroll([
      for (final player in _requests)
        _PlayerRow(
          player: player,
          rank: _rankFor(player.publicId),
          busy: _busyId == 'request-${player.publicId}',
          primaryLabel: context.tr('accept'),
          secondaryLabel: context.tr('decline'),
          onPrimary: () => _respondRequest(player, true),
          onSecondary: () => _respondRequest(player, false),
        ),
    ]);
  }

  Widget _playersView(List<SocialPlayer> players) {
    if (players.isEmpty) {
      return _Empty(message: context.tr('try_again_when_connected'));
    }
    return _scroll([
      for (final player in players)
        _PlayerRow(
          player: player,
          rank: _rankFor(player.publicId),
          busy: _busyId == 'challenge-${player.publicId}',
          primaryLabel: context.tr('challenge'),
          onPrimary: () => _challenge(player),
        ),
    ]);
  }

  Widget _recentOpponentsView() {
    if (_opponents.isEmpty) {
      return _Empty(message: context.tr('recent_opponents_empty_body'));
    }
    return _scroll([
      for (final player in _opponents)
        _PlayerRow(
          player: player,
          rank: _rankFor(player.publicId),
          busy: _busyId == 'friend-${player.publicId}',
          enabled:
              player.friendshipStatus != 'accepted' &&
              player.friendshipStatus != 'pending',
          primaryLabel: player.friendshipStatus == 'accepted'
              ? context.tr('friends')
              : player.friendshipStatus == 'pending'
              ? context.tr('friend_request_sent')
              : context.tr('add_friend'),
          onPrimary: () => _sendFriendRequest(player),
        ),
    ]);
  }

  Widget _challengesView() {
    if (_incoming.isEmpty) {
      return _Empty(message: context.tr('challenge_timed_out'));
    }
    return _scroll([
      for (final challenge in _incoming)
        _ChallengeRow(
          challenge: challenge,
          rank: _rankFor(challenge.challenger.publicId),
          onTap: () => _openChallenge(challenge),
        ),
    ]);
  }

  Widget _scroll(List<Widget> children) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: children,
        ),
      ),
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({
    required this.challenge,
    required this.rank,
    required this.onTap,
  });

  final SocialChallenge challenge;
  final PublicRankSummary? rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minTileHeight: 76,
        leading: PlayerAvatar(
          displayName: challenge.challenger.displayName,
          avatarKey:
              rank?.avatarKey ?? 'social-${challenge.challenger.publicId}',
          radius: 24,
        ),
        title: Text(
          challenge.challenger.displayName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${context.strings.difficultyLabel(_difficulty(challenge.difficulty))} · '
          '${rank == null ? context.tr('games_count', <Object>[challenge.challenger.gamesPlayed]) : '${rank!.rankName} · ${rank!.rankPoints} RP'}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.rank,
    required this.busy,
    required this.primaryLabel,
    required this.onPrimary,
    this.enabled = true,
    this.secondaryLabel,
    this.onSecondary,
  });

  final SocialPlayer player;
  final PublicRankSummary? rank;
  final bool busy;
  final bool enabled;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            PlayerAvatar(
              displayName: player.displayName,
              avatarKey: rank?.avatarKey ?? 'player-${player.publicId}',
              radius: 24,
            ),
            const SizedBox(width: 12),
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
                        ? '@${player.username} · ${context.tr('games_count', <Object>[player.gamesPlayed])}'
                        : '${rank!.rankName} · ${rank!.rankPoints} RP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (secondaryLabel != null)
              TextButton(
                onPressed: busy ? null : onSecondary,
                child: Text(secondaryLabel!),
              ),
            FilledButton.tonal(
              onPressed: busy || !enabled ? null : onPrimary,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(primaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

SudokuDifficulty _difficulty(String value) {
  return SudokuDifficulty.values.firstWhere(
    (difficulty) => difficulty.name == value,
    orElse: () => SudokuDifficulty.easy,
  );
}
