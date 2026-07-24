import 'package:flutter/material.dart';

import '../../services/platform_game_services.dart';

class PlatformSocialScreen extends StatefulWidget {
  const PlatformSocialScreen({super.key});

  @override
  State<PlatformSocialScreen> createState() => _PlatformSocialScreenState();
}

class _PlatformSocialScreenState extends State<PlatformSocialScreen> {
  final PlatformGameServices _services = PlatformGameServices.instance;

  bool _loading = true;
  bool _configured = false;
  bool _authenticated = false;
  String? _error;
  PlatformPlayer? _localPlayer;
  List<PlatformPlayer> _friends = const <PlatformPlayer>[];
  List<PlatformPlayer> _recentPlayers = const <PlatformPlayer>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final configured = await _services.isConfigured();
      if (!configured) {
        if (!mounted) return;
        setState(() {
          _configured = false;
          _authenticated = false;
          _loading = false;
        });
        return;
      }

      final authenticated = await _services.refreshAuthentication();
      PlatformPlayer? localPlayer;
      var friends = const <PlatformPlayer>[];
      var recent = const <PlatformPlayer>[];
      if (authenticated) {
        localPlayer = await _services.getLocalPlayer();
        friends = await _loadFriendsSafely();
        recent = await _loadRecentPlayersSafely();
      }

      if (!mounted) return;
      setState(() {
        _configured = true;
        _authenticated = authenticated;
        _localPlayer = localPlayer;
        _friends = friends;
        _recentPlayers = recent;
        _loading = false;
      });
    } on PlatformGameServicesException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<List<PlatformPlayer>> _loadFriendsSafely() async {
    try {
      return await _services.loadFriends();
    } on PlatformGameServicesException catch (error) {
      if (error.code == 'friends_consent_denied') return const <PlatformPlayer>[];
      rethrow;
    }
  }

  Future<List<PlatformPlayer>> _loadRecentPlayersSafely() async {
    try {
      return await _services.loadRecentPlayers();
    } on PlatformGameServicesException catch (error) {
      if (error.code == 'unsupported_platform') return const <PlatformPlayer>[];
      return const <PlatformPlayer>[];
    }
  }

  Future<void> _authenticate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _services.authenticate();
      await _refresh();
    } on PlatformGameServicesException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
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
                      title: 'Platform service error',
                      body: _error!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!_configured)
                    const _MessageCard(
                      icon: Icons.settings_outlined,
                      title: 'Platform setup required',
                      body:
                          'Complete the Play Games or Game Center console setup before platform friends, leaderboards, and achievements can be used.',
                    )
                  else if (!_authenticated)
                    _SignInCard(onPressed: _authenticate)
                  else ...[
                    _LocalPlayerCard(player: _localPlayer),
                    const SizedBox(height: 12),
                    _PlatformActions(services: _services),
                    const SizedBox(height: 22),
                    const _SearchPlaceholder(),
                    const SizedBox(height: 22),
                    _PlayerSection(
                      title: 'Platform friends',
                      emptyText:
                          'No platform friends are available, or friend access was not granted.',
                      players: _friends,
                      onProfile: _showProfile,
                      onChallenge: _challenge,
                    ),
                    const SizedBox(height: 22),
                    _PlayerSection(
                      title: 'Recent opponents',
                      emptyText:
                          'Recent cross-platform opponents will appear after the shared challenge backend is connected.',
                      players: _recentPlayers,
                      onProfile: _showProfile,
                      onChallenge: _challenge,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Future<void> _showProfile(PlatformPlayer player) async {
    try {
      await _services.showPlayerProfile(player.playerId);
    } on PlatformGameServicesException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  void _challenge(PlatformPlayer player) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Challenge delivery for ${player.displayName} will activate after the shared backend and push credentials are connected.',
        ),
      ),
    );
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
              'Connect your game profile',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in with Play Games or Game Center to see platform friends, leaderboards, achievements, and profiles.',
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

class _LocalPlayerCard extends StatelessWidget {
  const _LocalPlayerCard({required this.player});

  final PlatformPlayer? player;

  @override
  Widget build(BuildContext context) {
    final value = player;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(
          value?.displayName ?? 'Connected player',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          value?.platform == 'game_center' ? 'Game Center' : 'Google Play Games',
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
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder();

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: false,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        labelText: 'Search Sudoku Duel username',
        helperText:
            'Global username search activates when the shared social backend is deployed.',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _PlayerSection extends StatelessWidget {
  const _PlayerSection({
    required this.title,
    required this.emptyText,
    required this.players,
    required this.onProfile,
    required this.onChallenge,
  });

  final String title;
  final String emptyText;
  final List<PlatformPlayer> players;
  final ValueChanged<PlatformPlayer> onProfile;
  final ValueChanged<PlatformPlayer> onChallenge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
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
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.person_outline)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        player.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open platform profile',
                      onPressed: () => onProfile(player),
                      icon: const Icon(Icons.account_circle_outlined),
                    ),
                    FilledButton(
                      onPressed: () => onChallenge(player),
                      child: const Text('Challenge'),
                    ),
                  ],
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
