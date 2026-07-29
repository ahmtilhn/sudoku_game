import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/social_api_client.dart';
import '../../widgets/adaptive_app_shell.dart';
import 'competitive_profile_card.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile'))),
      body: AdaptivePageContainer(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _profile != null
            ? RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [CompetitiveProfileCard(profile: _profile!)],
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: Text(context.tr('online_account_unavailable')),
                      subtitle: Text(
                        _error ?? context.tr('try_again_when_connected'),
                      ),
                      trailing: IconButton(
                        tooltip: context.tr('retry'),
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
