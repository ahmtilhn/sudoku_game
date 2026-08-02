import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
import '../../widgets/app_backdrop.dart';

class GooglePlayGamesScreen extends StatefulWidget {
  const GooglePlayGamesScreen({super.key});

  @override
  State<GooglePlayGamesScreen> createState() => _GooglePlayGamesScreenState();
}

class _GooglePlayGamesScreenState extends State<GooglePlayGamesScreen> {
  final PlatformGameServices _games = PlatformGameServices.instance;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<bool> _connect() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      if (!await _games.isConfigured()) {
        throw const PlatformGameServicesException(
          'not_configured',
          'Google Play Games is not configured for this build.',
        );
      }
      var authenticated = await _games.refreshAuthentication();
      if (!authenticated) {
        authenticated = await _games.authenticate();
      }
      if (!authenticated) {
        throw const PlatformGameServicesException(
          'sign_in_required',
          'Google Play Games sign-in was not completed.',
        );
      }
      return true;
    } on PlatformGameServicesException catch (error) {
      if (mounted) setState(() => _error = '${error.code}: ${error.message}');
      return false;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLeaderboard(PlatformLeaderboardScope scope) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opened = await PlatformLeaderboardService.instance.show(scope);
      if (!opened) {
        throw const PlatformGameServicesException(
          'leaderboard_unavailable',
          'The Google Play leaderboard could not be opened.',
        );
      }
    } on PlatformGameServicesException catch (error) {
      if (mounted) setState(() => _error = '${error.code}: ${error.message}');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAchievements() async {
    if (!await _connect()) return;
    setState(() => _busy = true);
    try {
      final opened = await _games.showAchievements();
      if (!opened) {
        throw const PlatformGameServicesException(
          'achievements_unavailable',
          'Google Play achievements could not be opened.',
        );
      }
    } on PlatformGameServicesException catch (error) {
      if (mounted) setState(() => _error = '${error.code}: ${error.message}');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Play Games')),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _games.authenticated,
                    builder: (context, authenticated, _) {
                      return ValueListenableBuilder<PlatformPlayer?>(
                        valueListenable: _games.localPlayer,
                        builder: (context, player, _) {
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.sports_esports),
                              ),
                              title: Text(
                                authenticated
                                    ? player?.displayName ?? 'Google Play Player'
                                    : 'Google Play Games',
                              ),
                              subtitle: Text(
                                authenticated
                                    ? 'Connected'
                                    : 'Not connected',
                              ),
                              trailing: _busy
                                  ? const SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : authenticated
                                  ? const Icon(Icons.check_circle_outline)
                                  : FilledButton.tonal(
                                      onPressed: _connect,
                                      child: const Text('Connect'),
                                    ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: const Text('Play Games error'),
                        subtitle: Text(_error!),
                        trailing: IconButton(
                          tooltip: context.tr('retry'),
                          onPressed: _busy ? null : _connect,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    context.tr('leaderboards'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  _LeaderboardTile(
                    icon: Icons.public,
                    title: context.tr('global_elo'),
                    onTap: _busy
                        ? null
                        : () => _openLeaderboard(
                            PlatformLeaderboardScope.global,
                          ),
                  ),
                  _LeaderboardTile(
                    icon: Icons.looks_one_outlined,
                    title: context.tr('difficulty_beginner'),
                    onTap: _busy
                        ? null
                        : () => _openLeaderboard(
                            PlatformLeaderboardScope.beginner,
                          ),
                  ),
                  _LeaderboardTile(
                    icon: Icons.looks_two_outlined,
                    title: context.tr('difficulty_easy'),
                    onTap: _busy
                        ? null
                        : () => _openLeaderboard(
                            PlatformLeaderboardScope.easy,
                          ),
                  ),
                  _LeaderboardTile(
                    icon: Icons.looks_3_outlined,
                    title: context.tr('difficulty_medium'),
                    onTap: _busy
                        ? null
                        : () => _openLeaderboard(
                            PlatformLeaderboardScope.medium,
                          ),
                  ),
                  _LeaderboardTile(
                    icon: Icons.looks_4_outlined,
                    title: context.tr('difficulty_hard'),
                    onTap: _busy
                        ? null
                        : () => _openLeaderboard(
                            PlatformLeaderboardScope.hard,
                          ),
                  ),
                  _LeaderboardTile(
                    icon: Icons.workspace_premium_outlined,
                    title: context.tr('difficulty_expert'),
                    onTap: _busy
                        ? null
                        : () => _openLeaderboard(
                            PlatformLeaderboardScope.expert,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.emoji_events_outlined),
                      title: const Text('Achievements'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _openAchievements,
                    ),
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

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
