import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../localization/ux_copy.dart';
import '../../services/platform_game_services.dart';
import '../../services/platform_leaderboard_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';

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

  String get _platformTitle {
    if (kIsWeb) return context.tr('leaderboards');
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'Game Center'
        : 'Google Play Games';
  }

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
        throw PlatformGameServicesException(
          'not_configured',
          '$_platformTitle is not configured for this app.',
        );
      }

      var authenticated = await _games.refreshAuthentication();
      if (!authenticated && prompt) {
        authenticated = await _games.authenticate(notifyAccountBridge: false);
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
      authenticated = await _games.authenticate(notifyAccountBridge: false);
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
        throw PlatformGameServicesException(
          'leaderboard_unavailable',
          '$_platformTitle leaderboard could not be opened.',
        );
      }
      await _games.refreshAuthentication();
    } on PlatformGameServicesException catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
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
        throw PlatformGameServicesException(
          'authentication_failed',
          '$_platformTitle authentication could not be completed.',
        );
      }
      final opened = await _games.showAchievements();
      if (!opened) {
        throw PlatformGameServicesException(
          'achievements_unavailable',
          '$_platformTitle achievements could not be opened.',
        );
      }
    } on PlatformGameServicesException catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = switch ((_configured, _authenticated)) {
      (false, _) => 'Not configured',
      (true, true) => context.tr('connected'),
      (true, false) => context.tr('online_account_unavailable'),
      _ => 'Checking connection',
    };
    final title = _platformTitle;

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _PlatformHeader(
                    title: title,
                    busy: _busy,
                    onBack: () => Navigator.of(context).pop(),
                    onRefresh: () => _refreshConnection(prompt: false),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 12),
                  _ConnectionPanel(
                    title: title,
                    statusText: statusText,
                    authenticated: _authenticated,
                    player: _player,
                    busy: _busy,
                    onConnect: () => _refreshConnection(prompt: true),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _InlineError(
                      title: context.tr('online_account_unavailable'),
                      message: _error!,
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    context.tr('leaderboards'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LeaderboardTile(
                    asset: DuelAsset.leaderboardCrownPro,
                    title: context.tr('global_elo'),
                    onTap: _busy
                        ? null
                        : () =>
                              _openLeaderboard(PlatformLeaderboardScope.global),
                  ),
                  for (final item in <(String, PlatformLeaderboardScope)>[
                    (
                      context.tr('difficulty_beginner'),
                      PlatformLeaderboardScope.beginner,
                    ),
                    (
                      context.tr('difficulty_easy'),
                      PlatformLeaderboardScope.easy,
                    ),
                    (
                      context.tr('difficulty_medium'),
                      PlatformLeaderboardScope.medium,
                    ),
                    (
                      context.tr('difficulty_hard'),
                      PlatformLeaderboardScope.hard,
                    ),
                    (
                      context.tr('difficulty_expert'),
                      PlatformLeaderboardScope.expert,
                    ),
                  ])
                    _LeaderboardTile(
                      asset: DuelAsset.trophy,
                      title: item.$1,
                      onTap: _busy ? null : () => _openLeaderboard(item.$2),
                    ),
                  const SizedBox(height: 6),
                  _LeaderboardTile(
                    asset: DuelAsset.profilePro,
                    title: context.tr('achievement_showcase'),
                    onTap: _busy ? null : _openAchievements,
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

class _PlatformHeader extends StatelessWidget {
  const _PlatformHeader({
    required this.title,
    required this.busy,
    required this.onBack,
    required this.onRefresh,
  });

  final String title;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 10),
        const DuelAssetIcon(DuelAsset.leaderboardCrownPro, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: context.tr('refresh'),
          onPressed: busy ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.title,
    required this.statusText,
    required this.authenticated,
    required this.player,
    required this.busy,
    required this.onConnect,
  });

  final String title;
  final String statusText;
  final bool authenticated;
  final PlatformPlayer? player;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final displayName = player?.effectiveDisplayName ?? title;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (authenticated ? const Color(0xFF29D398) : Colors.white)
              .withValues(alpha: authenticated ? .34 : .08),
        ),
      ),
      child: Row(
        children: [
          PlayerAvatar(
            displayName: displayName,
            avatarKey: 'platform-services-player',
            localAvatarBytes: player?.avatarBytes,
            remoteApprovedImageUrl: player?.avatarUrl,
            radius: 27,
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
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: TextStyle(
                    color: authenticated
                        ? const Color(0xFF29D398)
                        : Colors.white.withValues(alpha: .58),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (!authenticated)
            FilledButton(
              onPressed: busy ? null : onConnect,
              child: Text(context.tr('continue_action')),
            ),
        ],
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({
    required this.asset,
    required this.title,
    required this.onTap,
  });

  final String asset;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728).withValues(alpha: .82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
            ),
            child: Row(
              children: [
                DuelAssetIcon(asset, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: .58),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF3A151D).withValues(alpha: .74),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF5B6B).withValues(alpha: .3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFFB4AB)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  message,
                  style: TextStyle(color: Colors.white.withValues(alpha: .68)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
