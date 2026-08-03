import 'dart:io';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        if (_profile != null)
                          CompetitiveProfileCard(profile: _profile!),
                        if (_error != null)
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: ListTile(
                              leading: const Icon(Icons.cloud_off_outlined),
                              title: Text(
                                context.tr('online_account_unavailable'),
                              ),
                              subtitle: Text(_error!),
                              trailing: IconButton(
                                tooltip: context.tr('retry'),
                                onPressed: _load,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        _ProfileAction(
                          icon: Icons.people_alt_outlined,
                          title: context.tr('friends_challenges'),
                          subtitle: context.tr('friend_requests'),
                          onTap: () => _open(const SocialHubScreen()),
                        ),
                        _ProfileAction(
                          icon: Icons.receipt_long_outlined,
                          title: context.tr('coin_history'),
                          subtitle: context.tr('server_wallet_history'),
                          onTap: () => _open(const WalletHistoryScreen()),
                        ),
                        if (Platform.isAndroid || Platform.isIOS)
                          _ProfileAction(
                            icon: Icons.sports_esports_outlined,
                            title: Platform.isIOS
                                ? 'Game Center'
                                : 'Google Play Games',
                            subtitle: context.tr('leaderboards'),
                            onTap: () =>
                                _open(const PlatformServicesScreen()),
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

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minTileHeight: 68,
        leading: Icon(icon, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
