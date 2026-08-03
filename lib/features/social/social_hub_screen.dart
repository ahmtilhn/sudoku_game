import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/player_profile_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/player_avatar.dart';
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
  List<SocialPlayer> _friends = const <SocialPlayer>[];
  List<SocialPlayer> _requests = const <SocialPlayer>[];
  List<SocialPlayer> _opponents = const <SocialPlayer>[];
  List<SocialChallenge> _challenges = const <SocialChallenge>[];
  List<SocialPlayer> _results = const <SocialPlayer>[];
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        PlayerProfileService.instance.load(),
        _social.loadFriends(),
        _social.loadIncomingFriendRequests(),
        _social.loadPendingChallenges(),
        _social.loadRecentOpponents(),
      ]);
      if (!mounted) return;
      setState(() {
        _me = values[0] as PlayerProfilePreferences;
        _friends = values[1] as List<SocialPlayer>;
        _requests = values[2] as List<SocialPlayer>;
        _challenges = values[3] as List<SocialChallenge>;
        _opponents = values[4] as List<SocialPlayer>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(String id, Future<void> Function() action) async {
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

  Future<void> _searchPlayers() async {
    final query = _search.text.trim();
    if (query.length < 3 || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _social.searchPlayers(query);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _chooseChallenge(SocialPlayer player) async {
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
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            for (final difficulty in SudokuDifficulty.values)
              ListTile(
                minTileHeight: 52,
                leading: const Icon(Icons.grid_4x4_rounded),
                title: Text(
                  context.strings.difficultyLabel(difficulty),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(sheetContext).pop(difficulty),
              ),
          ],
        ),
      ),
    );
    if (difficulty == null) return;
    await _run('challenge-${player.publicId}', () async {
      await _social.createChallenge(
        recipientPublicId: player.publicId,
        difficulty: difficulty.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('rematch_invitation_sent'))),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('friends_challenges')),
        actions: [
          IconButton(
            tooltip: context.tr('refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: '${context.tr('friend_requests')} (${_requests.length})'),
            Tab(text: '${context.tr('friends')} (${_friends.length})'),
            Tab(text: '${context.tr('challenge')} (${_incoming.length})'),
            Tab(text: context.tr('opponent')),
          ],
        ),
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    children: [
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
                            onPressed: _searching ? null : _searchPlayers,
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
                        onSubmitted: (_) => _searchPlayers(),
                      ),
                      if (_results.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Card(
                          child: Column(
                            children: [
                              for (final player in _results.take(5))
                                _PlayerTile(
                                  player: player,
                                  busy: _busyId == 'friend-${player.publicId}',
                                  primaryLabel: context.tr('add_friend'),
                                  onPrimary: () => _run(
                                    'friend-${player.publicId}',
                                    () async {
                                      await _social.sendFriendRequest(
                                        player.publicId,
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            context.tr('friend_request_sent'),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
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
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _requestList(),
                          _playerList(_friends),
                          _challengeList(),
                          _playerList(_opponents),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<SocialChallenge> get _incoming {
    final id = _me?.publicId;
    return _challenges
        .where(
          (challenge) =>
              challenge.recipient.publicId == id &&
              challenge.status == 'pending',
        )
        .toList(growable: false);
  }

  Widget _requestList() {
    if (_requests.isEmpty) {
      return _EmptyPanel(message: context.tr('friend_requests_empty'));
    }
    return _listView([
      for (final player in _requests)
        _PlayerTile(
          player: player,
          busy: _busyId == 'request-${player.publicId}',
          primaryLabel: context.tr('accept'),
          secondaryLabel: context.tr('decline'),
          onPrimary: () => _run('request-${player.publicId}', () async {
            await _social.respondToFriendRequest(
              requesterPublicId: player.publicId,
              accept: true,
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.tr('friend_request_accepted', <Object>[
                    player.displayName,
                  ]),
                ),
              ),
            );
          }),
          onSecondary: () => _run('request-${player.publicId}', () async {
            await _social.respondToFriendRequest(
              requesterPublicId: player.publicId,
              accept: false,
            );
          }),
        ),
    ]);
  }

  Widget _playerList(List<SocialPlayer> players) {
    if (players.isEmpty) {
      return _EmptyPanel(message: context.tr('try_again_when_connected'));
    }
    return _listView([
      for (final player in players)
        _PlayerTile(
          player: player,
          busy: _busyId == 'challenge-${player.publicId}',
          primaryLabel: context.tr('challenge'),
          onPrimary: () => _chooseChallenge(player),
        ),
    ]);
  }

  Widget _challengeList() {
    if (_incoming.isEmpty) {
      return _EmptyPanel(message: context.tr('challenge_timed_out'));
    }
    return _listView([
      for (final challenge in _incoming)
        Card(
          child: ListTile(
            minTileHeight: 76,
            leading: PlayerAvatar(
              displayName: challenge.challenger.displayName,
              avatarKey: 'social-${challenge.challenger.publicId}',
              radius: 24,
            ),
            title: Text(
              challenge.challenger.displayName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${context.strings.difficultyLabel(_difficulty(challenge.difficulty))} · ${context.tr('rating_value', <Object>[challenge.challenger.rating])}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => UxChallengeInvitationScreen(
                    challengeId: challenge.id,
                  ),
                ),
              );
              await _load();
            },
          ),
        ),
    ]);
  }

  Widget _listView(List<Widget> children) {
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

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.busy,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final SocialPlayer player;
  final bool busy;
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
              avatarKey: 'player-${player.publicId}',
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
                    context.tr('player_rating_summary', <Object>[
                      player.username,
                      player.rating,
                    ]),
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
              onPressed: busy ? null : onPrimary,
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

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

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
