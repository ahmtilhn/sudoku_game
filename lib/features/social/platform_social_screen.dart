import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../localization/ux_copy.dart';
import '../../services/platform_game_services.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../duel/online_duel_screen.dart';
import 'competitive_profile_card.dart';

class PlatformSocialScreen extends StatefulWidget {
  const PlatformSocialScreen({super.key});

  @override
  State<PlatformSocialScreen> createState() => _PlatformSocialScreenState();
}

class _PlatformSocialScreenState extends State<PlatformSocialScreen> {
  final PlatformGameServices _platform = PlatformGameServices.instance;
  final SocialApiClient _social = SocialApiClient.instance;
  final PushNotificationService _push = PushNotificationService.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _searching = false;
  bool _platformConfigured = false;
  bool _platformAuthenticated = false;
  String? _error;
  PlatformPlayer? _platformPlayer;
  SocialPlayer? _socialPlayer;
  CompetitiveProfile? _competitiveProfile;
  List<PlatformPlayer> _platformFriends = const <PlatformPlayer>[];
  List<SocialPlayer> _friends = const <SocialPlayer>[];
  List<SocialPlayer> _recentOpponents = const <SocialPlayer>[];
  List<SocialPlayer> _searchResults = const <SocialPlayer>[];
  List<SocialChallenge> _pendingChallenges = const <SocialChallenge>[];

  bool get _backendReady => _push.configured && _social.configured;

  @override
  void initState() {
    super.initState();
    _push.openedChallengeId.addListener(_handleOpenedChallenge);
    _refresh();
  }

  @override
  void dispose() {
    _push.openedChallengeId.removeListener(_handleOpenedChallenge);
    _searchController.dispose();
    super.dispose();
  }

  void _handleOpenedChallenge() {
    final challengeId = _push.openedChallengeId.value;
    if (challengeId == null || challengeId.isEmpty || !_backendReady) return;
    _push.openedChallengeId.value = null;
    _refreshSocial(showLoading: false);
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    await _refreshPlatform();
    await _refreshSocial(showLoading: false);

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshPlatform() async {
    try {
      final configured = await _platform.isConfigured();
      var authenticated = false;
      PlatformPlayer? localPlayer;
      var friends = const <PlatformPlayer>[];

      if (configured) {
        authenticated = await _platform.refreshAuthentication();
        if (authenticated) {
          localPlayer = await _platform.getLocalPlayer();
          friends = await _loadPlatformFriendsSafely();
        }
      }

      if (!mounted) return;
      setState(() {
        _platformConfigured = configured;
        _platformAuthenticated = authenticated;
        _platformPlayer = localPlayer;
        _platformFriends = friends;
      });
    } on PlatformGameServicesException catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    }
  }

  Future<void> _refreshSocial({required bool showLoading}) async {
    if (!_backendReady) return;
    if (showLoading && mounted) setState(() => _loading = true);

    try {
      await _push.initialize();
      final profile = await _social.ensureProfile(
        displayName: _platformPlayer?.displayName,
      );
      final friends = await _social.loadFriends();
      final recentOpponents = await _social.loadRecentOpponents();
      final pendingChallenges = await _social.loadPendingChallenges();
      final competitiveProfile = await _social.loadCompetitiveProfile();

      if (!mounted) return;
      setState(() {
        _socialPlayer = profile;
        _competitiveProfile = competitiveProfile;
        _friends = friends;
        _recentOpponents = recentOpponents;
        _pendingChallenges = pendingChallenges;
      });
    } on SocialApiException catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Social services could not be initialized: $error';
        });
      }
    } finally {
      if (showLoading && mounted) setState(() => _loading = false);
    }
  }

  Future<List<PlatformPlayer>> _loadPlatformFriendsSafely() async {
    try {
      return await _platform.loadFriends();
    } on PlatformGameServicesException catch (error) {
      if (error.code == 'friends_consent_denied' ||
          error.code == 'unsupported_platform') {
        return const <PlatformPlayer>[];
      }
      rethrow;
    }
  }

  Future<void> _authenticatePlatform() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await _platform.authenticate();
      await _refreshPlatform();
      await _refreshSocial(showLoading: false);
    } on PlatformGameServicesException catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enableChallengeNotifications() async {
    final enabled = await _push.requestPermissionAndRegister();
    _showMessage(
      enabled
          ? 'Challenge notifications are enabled.'
          : 'Notification permission or push configuration is unavailable.',
    );
    if (mounted) setState(() {});
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 3 || !_backendReady) return;

    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _social.searchPlayers(query);
      if (mounted) setState(() => _searchResults = results);
    } on SocialApiException catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends & challenges'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_error != null) ...[
                    _MessageCard(
                      icon: Icons.error_outline,
                      title: 'Service message',
                      body: _error!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildBackendStatus(),
                  const SizedBox(height: 12),
                  _buildPlatformStatus(),
                  if (_backendReady && _socialPlayer != null) ...[
                    const SizedBox(height: 20),
                    CompetitiveProfileCard(
                      profile:
                          _competitiveProfile ??
                          CompetitiveProfile(
                            publicId: _socialPlayer!.publicId,
                            username: _socialPlayer!.username,
                            displayName: _socialPlayer!.displayName,
                            avatarKey: 'default',
                            currentElo: _socialPlayer!.rating,
                            rankName: 'Bronze',
                            seasonPeak: _socialPlayer!.rating,
                            wins: _socialPlayer!.wins,
                            losses:
                                _socialPlayer!.gamesPlayed -
                                _socialPlayer!.wins,
                            draws: 0,
                            winRate: _socialPlayer!.winRate,
                            winStreak: 0,
                            tournamentEntries: 0,
                            tournamentPodiums: 0,
                            countryContributions: 0,
                            achievementCount: _socialPlayer!.achievementCount,
                            achievementShowcase: const <SocialAchievement>[],
                            privateProfile: false,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _buildNotificationCard(),
                    const SizedBox(height: 22),
                    _buildSearch(),
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _SocialPlayerSection(
                        title: 'Search results',
                        emptyText: '',
                        players: _searchResults,
                        onChallenge: _challenge,
                        onAddFriend: _addFriend,
                      ),
                    ],
                    const SizedBox(height: 22),
                    _buildPendingChallenges(),
                    const SizedBox(height: 22),
                    _SocialPlayerSection(
                      title: 'Sudoku Duel friends',
                      emptyText:
                          'Search a username and send a friend request to build your list.',
                      players: _friends,
                      onChallenge: _challenge,
                    ),
                    const SizedBox(height: 22),
                    _SocialPlayerSection(
                      title: 'Recent opponents',
                      emptyText:
                          'Players you finish an online match with will appear here.',
                      players: _recentOpponents,
                      onChallenge: _challenge,
                      onAddFriend: _addFriend,
                    ),
                  ],
                  if (_platformAuthenticated) ...[
                    const SizedBox(height: 22),
                    _PlatformActions(services: _platform),
                    const SizedBox(height: 22),
                    _PlatformPlayerSection(
                      players: _platformFriends,
                      onProfile: _showPlatformProfile,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildBackendStatus() {
    if (!_backendReady) {
      return _MessageCard(
        icon: Icons.cloud_off_outlined,
        title: context.tr('online_account_unavailable'),
        body: UxCopy.accountError(context),
      );
    }
    return const _MessageCard(
      icon: Icons.cloud_done_outlined,
      title: 'Cross-platform social service',
      body:
          'Sudoku Duel usernames, friends, recent opponents, and challenges are connected through the shared backend.',
    );
  }

  Widget _buildPlatformStatus() {
    if (!_platformConfigured) {
      return _MessageCard(
        icon: Icons.sports_esports_outlined,
        title: context.tr('online_account_unavailable'),
        body: UxCopy.platformNotConnected(context),
      );
    }
    if (!_platformAuthenticated) {
      return _SignInCard(onPressed: _authenticatePlatform);
    }
    return _PlatformProfileCard(player: _platformPlayer);
  }

  Widget _buildNotificationCard() {
    return ValueListenableBuilder<bool>(
      valueListenable: _push.permissionGranted,
      builder: (context, granted, _) => Card(
        child: ListTile(
          leading: Icon(
            granted
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
          ),
          title: Text(
            granted
                ? 'Challenge notifications enabled'
                : 'Enable challenge notifications',
          ),
          subtitle: const Text(
            'Receive invitations and responses even while Sudoku Duel is closed.',
          ),
          trailing: granted
              ? const Icon(Icons.check_circle_outline)
              : FilledButton(
                  onPressed: _enableChallengeNotifications,
                  child: const Text('Enable'),
                ),
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        labelText: 'Search Sudoku Duel username',
        helperText: 'Enter at least 3 characters.',
        border: const OutlineInputBorder(),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: 'Search',
                onPressed: _search,
                icon: const Icon(Icons.search),
              ),
      ),
    );
  }

  Widget _buildPendingChallenges() {
    final current = _socialPlayer;
    final incoming = _pendingChallenges
        .where((challenge) => challenge.recipient.publicId == current?.publicId)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending challenges',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (incoming.isEmpty)
          const _MessageCard(
            icon: Icons.bolt_outlined,
            title: 'No pending challenges',
            body:
                'New invitations will appear here and can also arrive by push notification.',
          )
        else
          for (final challenge in incoming)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.bolt_outlined)),
                title: Text(
                  challenge.challenger.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${_difficultyLabel(challenge.difficulty)} challenge · expires ${_shortTime(challenge.expiresAt)}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Decline',
                      onPressed: () => _respondChallenge(challenge, false),
                      icon: const Icon(Icons.close),
                    ),
                    FilledButton(
                      onPressed: () => _respondChallenge(challenge, true),
                      child: const Text('Accept'),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _showPlatformProfile(PlatformPlayer player) async {
    try {
      await _platform.showPlayerProfile(player.playerId);
    } on PlatformGameServicesException catch (error) {
      _showMessage(UserSafeError.message(context, error));
    }
  }

  Future<void> _addFriend(SocialPlayer player) async {
    try {
      await _social.sendFriendRequest(player.publicId);
      _showMessage('Friend request sent to ${player.displayName}.');
      await _refreshSocial(showLoading: false);
    } on SocialApiException catch (error) {
      _showMessage(UserSafeError.message(context, error));
    }
  }

  Future<void> _challenge(SocialPlayer player) async {
    final difficulty = await showDialog<SudokuDifficulty>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Challenge ${player.displayName}'),
        children: [
          for (final value in SudokuDifficulty.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: ListTile(
                leading: const Icon(Icons.grid_view_outlined),
                title: Text(context.strings.difficultyLabel(value)),
              ),
            ),
        ],
      ),
    );
    if (difficulty == null) return;

    try {
      await _social.createChallenge(
        recipientPublicId: player.publicId,
        difficulty: difficulty.name,
      );
      _showMessage('Challenge sent to ${player.displayName}.');
      await _refreshSocial(showLoading: false);
    } on SocialApiException catch (error) {
      _showMessage(UserSafeError.message(context, error));
    }
  }

  Future<void> _respondChallenge(SocialChallenge challenge, bool accept) async {
    try {
      final updated = await _social.respondToChallenge(
        challengeId: challenge.id,
        accept: accept,
      );
      if (!mounted) return;
      if (accept && updated.roomId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OnlineDuelScreen(roomId: updated.roomId!),
          ),
        );
      } else {
        _showMessage('Challenge declined.');
      }
      await _refreshSocial(showLoading: false);
    } on SocialApiException catch (error) {
      _showMessage(UserSafeError.message(context, error));
    }
  }

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _difficultyLabel(String value) {
    return value.isEmpty
        ? 'Easy'
        : '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _shortTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.sports_esports_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              'Connect your platform profile',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use Play Games or Game Center for native friends, leaderboards, achievements, and player profiles.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.login),
              label: const Text('Connect platform profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformProfileCard extends StatelessWidget {
  const _PlatformProfileCard({required this.player});

  final PlatformPlayer? player;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(
          player?.displayName ?? 'Connected player',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          player?.platform == 'game_center'
              ? 'Game Center'
              : 'Google Play Games',
        ),
        trailing: const Icon(Icons.verified_outlined),
      ),
    );
  }
}

class _PlatformActions extends StatelessWidget {
  const _PlatformActions({required this.services});

  final PlatformGameServices services;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => _run(context, services.showLeaderboard),
          icon: const Icon(Icons.leaderboard_outlined),
          label: const Text('Leaderboard'),
        ),
        OutlinedButton.icon(
          onPressed: () => _run(context, services.showAchievements),
          icon: const Icon(Icons.emoji_events_outlined),
          label: const Text('Achievements'),
        ),
        OutlinedButton.icon(
          onPressed: () => _run(context, services.showFriends),
          icon: const Icon(Icons.people_outline),
          label: const Text('Platform friends'),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    try {
      await action();
    } on PlatformGameServicesException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserSafeError.message(context, error))),
      );
    }
  }
}

class _PlatformPlayerSection extends StatelessWidget {
  const _PlatformPlayerSection({
    required this.players,
    required this.onProfile,
  });

  final List<PlatformPlayer> players;
  final ValueChanged<PlatformPlayer> onProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('platform_friends'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (players.isEmpty)
          _MessageCard(
            icon: Icons.people_outline,
            title: context.tr('platform_friends_empty_title'),
            body: context.tr('platform_friends_empty_body'),
          )
        else
          for (final player in players)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(
                  player.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(context.tr('open_native_platform_profile')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onProfile(player),
              ),
            ),
      ],
    );
  }
}

class _SocialPlayerSection extends StatelessWidget {
  const _SocialPlayerSection({
    required this.title,
    required this.emptyText,
    required this.players,
    required this.onChallenge,
    this.onAddFriend,
  });

  final String title;
  final String emptyText;
  final List<SocialPlayer> players;
  final ValueChanged<SocialPlayer> onChallenge;
  final ValueChanged<SocialPlayer>? onAddFriend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (players.isEmpty)
          _MessageCard(
            icon: Icons.people_outline,
            title: title,
            body: emptyText,
          )
        else
          for (final player in players)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        if (onAddFriend != null &&
                            player.friendshipStatus != 'accepted')
                          IconButton.outlined(
                            tooltip: context.tr('add_friend'),
                            onPressed: () => onAddFriend!(player),
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                          ),
                        FilledButton(
                          onPressed: () => onChallenge(player),
                          child: Text(context.tr('challenge')),
                        ),
                      ],
                    );
                    final details = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(child: Icon(Icons.person_outline)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                context
                                    .tr('player_rating_wins_summary', <Object>[
                                      player.username,
                                      player.rating,
                                      player.wins,
                                      player.gamesPlayed,
                                    ]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

                    if (constraints.maxWidth < 420) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          details,
                          const SizedBox(height: 10),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: actions,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: details),
                        const SizedBox(width: 12),
                        actions,
                      ],
                    );
                  },
                ),
              ),
            ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
