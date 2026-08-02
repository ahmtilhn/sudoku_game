import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import 'competitive_profile_card.dart';
import 'google_play_games_screen.dart';

class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({super.key});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  bool _loading = true;
  String? _error;
  CompetitiveProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.tr('online_account_unavailable'));
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
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
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
                  Text(
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
