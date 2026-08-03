import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';
import 'competitive_profile_card.dart';
import 'google_play_games_screen.dart';

class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({super.key});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  final PlatformGameServices _games = PlatformGameServices.instance;
  bool _loading = true;
  String? _error;
  CompetitiveProfile? _profile;

  @override
  void initState() {
    super.initState();
    _games.localPlayer.addListener(_onPlatformPlayerChanged);
    _load();
  }

  @override
  void dispose() {
    _games.localPlayer.removeListener(_onPlatformPlayerChanged);
    super.dispose();
  }

  void _onPlatformPlayerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await SocialApiClient.instance.loadCompetitiveProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } on SocialApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _error = 'Backend ${error.statusCode}: ${error.message}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _error = error.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openGooglePlayGames() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const GooglePlayGamesScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final platformPlayer = _games.localPlayer.value;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.tr('profile')),
        actions: [
          IconButton(
            tooltip: 'Google Play Games',
            onPressed: _openGooglePlayGames,
            icon: const Icon(Icons.sports_esports),
          ),
        ],
      ),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF29D398),
                        ),
                      )
                    : _profile != null
                    ? RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            CompetitiveProfileCard(profile: _profile!),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            if (platformPlayer != null) ...[
                              _GooglePlayIdentityPanel(player: platformPlayer),
                              const SizedBox(height: 12),
                            ],
                            _ProfileUnavailablePanel(
                              message:
                                  _error ??
                                  context.tr('try_again_when_connected'),
                              onRetry: _load,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GooglePlayIdentityPanel extends StatelessWidget {
  const _GooglePlayIdentityPanel({required this.player});

  final PlatformPlayer player;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF29D398).withValues(alpha: .34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            PlayerAvatar(
              displayName: player.displayName,
              avatarKey: 'google-play-${player.playerId}',
              remoteApprovedImageUrl: player.avatarUrl,
              radius: 27,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Google Play Games connected',
                    style: TextStyle(
                      color: Color(0xFF29D398),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    player.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Player ID: ${player.playerId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .58),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileUnavailablePanel extends StatelessWidget {
  const _ProfileUnavailablePanel({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF3AA9FF).withValues(alpha: .30),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const DuelAssetIcon(
              DuelAsset.cloud,
              size: 34,
              color: Color(0xFF3AA9FF),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('online_account_unavailable'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    message,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .66),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr('retry'),
              onPressed: onRetry,
              icon: const DuelAssetIcon(
                DuelAsset.refresh,
                size: 22,
                color: Color(0xFF29D398),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
