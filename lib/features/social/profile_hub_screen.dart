import 'dart:io';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../duel/leaderboards_screen.dart';
import '../economy/wallet_history_screen.dart';
import 'competitive_profile_card.dart';
import 'platform_services_screen.dart';
import 'social_hub_screen.dart';

class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({super.key});

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  CompetitiveProfile? _profile;
  bool _loading = true;
  String? _error;

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
      final value = await SocialApiClient.instance.loadCompetitiveProfile();
      if (mounted) setState(() => _profile = value);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('profile')),
        actions: [
          IconButton(
            tooltip: context.tr('refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                      children: [
                        _ProfileHeader(
                          hasProfile: _profile != null,
                          error: _error,
                          onRetry: _load,
                        ),
                        const SizedBox(height: 14),
                        if (_profile != null)
                          CompetitiveProfileCard(profile: _profile!),
                        if (_error != null)
                          _ProfileNotice(message: _error!, onRetry: _load),
                        const SizedBox(height: 14),
                        _ActionSection(
                          actions: [
                            _ProfileActionData(
                              asset: DuelAsset.people,
                              title: context.tr('friends_challenges'),
                              subtitle: context.tr('friend_requests'),
                              accent: const Color(0xFF3AA9FF),
                              onTap: () => _open(const SocialHubScreen()),
                            ),
                            _ProfileActionData(
                              asset: DuelAsset.coin,
                              title: context.tr('coin_history'),
                              subtitle: context.tr('server_wallet_history'),
                              accent: const Color(0xFFFFC94D),
                              onTap: () => _open(const WalletHistoryScreen()),
                            ),
                            _ProfileActionData(
                              asset: DuelAsset.leaderboardCrownPro,
                              title: context.tr('leaderboards'),
                              subtitle: context.tr('home_rating_label'),
                              accent: const Color(0xFFB7A9FF),
                              onTap: () => _open(const LeaderboardsScreen()),
                            ),
                            if (Platform.isAndroid || Platform.isIOS)
                              _ProfileActionData(
                                asset: DuelAsset.profilePro,
                                title: Platform.isIOS
                                    ? 'Game Center'
                                    : 'Google Play Games',
                                subtitle: context.tr('leaderboards'),
                                accent: const Color(0xFF29D398),
                                onTap: () =>
                                    _open(const PlatformServicesScreen()),
                              ),
                          ],
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.hasProfile,
    required this.error,
    required this.onRetry,
  });

  final bool hasProfile;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = error == null
        ? const Color(0xFF3AA9FF)
        : const Color(0xFFFF8A3D);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: DuelAssetIcon(
              hasProfile ? DuelAsset.profilePro : DuelAsset.wifi,
              size: 40,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('profile'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasProfile
                      ? context.tr('home_rating_label')
                      : context.tr('online_account_unavailable'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .66),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: context.tr('refresh'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _ProfileNotice extends StatelessWidget {
  const _ProfileNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8A3D).withValues(alpha: .11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF8A3D).withValues(alpha: .28),
        ),
      ),
      child: Row(
        children: [
          const DuelAssetIcon(DuelAsset.wifi, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: context.tr('retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({required this.actions});

  final List<_ProfileActionData> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 96,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) => _ProfileAction(actions[index]),
        );
      },
    );
  }
}

class _ProfileActionData {
  const _ProfileActionData({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final String asset;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction(this.action);

  final _ProfileActionData action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF101B20).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: action.accent.withValues(alpha: .24)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: action.accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: DuelAssetIcon(action.asset, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      action.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: action.accent),
            ],
          ),
        ),
      ),
    );
  }
}
