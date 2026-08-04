import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../localization/ux_copy.dart';
import '../../services/firebase_session_service.dart';
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
  bool _busy = false;
  bool? _configured;
  bool _authenticated = false;
  PlatformPlayer? _player;
  String? _error;

  @override
  void initState() {
    super.initState();
    _games.authenticated.addListener(_onPlatformStateChanged);
    _games.localPlayer.addListener(_onPlatformStateChanged);
    _games.lastError.addListener(_onPlatformStateChanged);
    _refreshConnection(prompt: false);
  }

  @override
  void dispose() {
    _games.authenticated.removeListener(_onPlatformStateChanged);
    _games.localPlayer.removeListener(_onPlatformStateChanged);
    _games.lastError.removeListener(_onPlatformStateChanged);
    super.dispose();
  }

  void _onPlatformStateChanged() {
    if (!mounted) return;
    setState(() {
      _authenticated = _games.authenticated.value;
      _player = _games.localPlayer.value;
      _error = _games.lastError.value == null
          ? null
          : UserSafeError.message(context, _games.lastError.value);
    });
  }

  Future<void> _refreshConnection({required bool prompt}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final configured = await _games.isConfigured();
      if (!configured) {
        throw const PlatformGameServicesException(
          'not_configured',
          'The Google Play Games project ID is not configured in the Android app.',
        );
      }

      var authenticated = await _games.refreshAuthentication();
      if (!authenticated && prompt) {
        authenticated = await _games.authenticate();
      }

      // A successful Play Games connection must also become the permanent
      // Firebase account. This preserves the same backend UID, nickname, Coin,
      // ELO and social profile after reinstalling the game.
      if (authenticated && prompt) {
        await FirebaseSessionService.connectPlayGamesAccount();
      }

      if (!mounted) return;
      setState(() {
        _configured = configured;
        _authenticated = authenticated;
        _player = _games.localPlayer.value;
        if (!authenticated && prompt) {
          _error = UxCopy.accountError(context);
        }
      });
    } on FirebaseSessionException catch (error) {
      if (!mounted) return;
      setState(() {
        _configured = true;
        _authenticated = _games.authenticated.value;
        _player = _games.localPlayer.value;
        _error = UserSafeError.message(context, error);
      });
    } on PlatformGameServicesException catch (error) {
      if (!mounted) return;
      setState(() {
        _configured = error.code == 'not_configured' ? false : _configured;
        _authenticated = false;
        _player = null;
        _error = UserSafeError.message(context, error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authenticated = false;
        _player = null;
        _error = UserSafeError.message(context, error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _ensureAuthenticated() async {
    if (!await _games.isConfigured()) return false;
    var authenticated = await _games.refreshAuthentication();
    if (!authenticated) {
      authenticated = await _games.authenticate();
    }
    if (authenticated) {
      await FirebaseSessionService.connectPlayGamesAccount();
    }
    if (mounted) {
      setState(() {
        _configured = true;
        _authenticated = authenticated;
        _player = _games.localPlayer.value;
        _error = _games.lastError.value == null
            ? null
            : UserSafeError.message(context, _games.lastError.value);
      });
    }
    return authenticated;
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
      await _games.refreshAuthentication();
    } on PlatformGameServicesException catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAchievements() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _ensureAuthenticated()) {
        throw const PlatformGameServicesException(
          'authentication_failed',
          'Google Play Games authentication could not be completed.',
        );
      }
      final opened = await _games.showAchievements();
      if (!opened) {
        throw const PlatformGameServicesException(
          'achievements_unavailable',
          'Google Play achievements could not be opened.',
        );
      }
    } on FirebaseSessionException catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } on PlatformGameServicesException catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = switch ((_configured, _authenticated)) {
      (false, _) => 'Not configured',
      (true, true) => 'Connected',
      (true, false) => 'Not connected',
      _ => 'Checking connection',
    };

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
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _authenticated
                                    ? Icons.check_circle_outline
                                    : Icons.cloud_off_outlined,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  statusText,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Check again',
                                onPressed: _busy
                                    ? null
                                    : () => _refreshConnection(prompt: false),
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),
                          if (_player != null) ...[
                            const SizedBox(height: 8),
                            Text('Player: ${_player!.displayName}'),
                            Text(
                              'Player ID: ${_player!.playerId}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (!_authenticated) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _refreshConnection(prompt: true),
                                icon: const Icon(Icons.login),
                                label: const Text('Connect / retry'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(context.tr('online_account_unavailable')),
                        subtitle: Text(_error!),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
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
                        : () =>
                              _openLeaderboard(PlatformLeaderboardScope.global),
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
                        : () => _openLeaderboard(PlatformLeaderboardScope.easy),
                  ),
                  _LeaderboardTile(
                    icon: Icons.looks_3_outlined,
                    title: context.tr('difficulty_medium'),
                    onTap: _busy
                        ? null
                        : () =>
                              _openLeaderboard(PlatformLeaderboardScope.medium),
                  ),
                  _LeaderboardTile(
                    icon: Icons.looks_4_outlined,
                    title: context.tr('difficulty_hard'),
                    onTap: _busy
                        ? null
                        : () => _openLeaderboard(PlatformLeaderboardScope.hard),
                  ),
                  _LeaderboardTile(
                    icon: Icons.workspace_premium_outlined,
                    title: context.tr('difficulty_expert'),
                    onTap: _busy
                        ? null
                        : () =>
                              _openLeaderboard(PlatformLeaderboardScope.expert),
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
