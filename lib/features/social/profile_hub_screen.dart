import 'dart:io';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../duel/leaderboards_screen.dart';
import 'competitive_profile_card.dart';
import 'platform_services_screen.dart';

enum _ProfileTab { leaderboards, platform }

class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({super.key});

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  final PlatformGameServices _games = PlatformGameServices.instance;
  CompetitiveProfile? _profile;
  bool _loading = true;
  String? _error;
  _ProfileTab _selectedTab = _ProfileTab.leaderboards;

  @override
  void initState() {
    super.initState();
    _games.localPlayer.addListener(_platformIdentityChanged);
    _refreshPlatformIdentity();
    _load();
  }

  @override
  void dispose() {
    _games.localPlayer.removeListener(_platformIdentityChanged);
    super.dispose();
  }

  void _platformIdentityChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshPlatformIdentity() async {
    try {
      if (!await _games.isConfigured()) return;
      final authenticated = await _games.refreshAuthentication();
      if (authenticated && _games.localPlayer.value == null) {
        _games.localPlayer.value = await _games.getLocalPlayer();
      }
    } catch (_) {
      // Remote profile remains usable without native platform identity.
    }
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
    final tabs = _tabs(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
        title: const SizedBox.shrink(),
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      children: [
                        if (_profile != null)
                          CompetitiveProfileCard(profile: _profile!),
                        if (_error != null)
                          _ProfileNotice(message: _error!, onRetry: _load),
                        const SizedBox(height: 14),
                        _ProfileTabs(
                          tabs: tabs,
                          selected: _selectedTab,
                          onSelected: (value) =>
                              setState(() => _selectedTab = value),
                        ),
                        const SizedBox(height: 12),
                        _ProfileTabPanel(
                          tab: tabs.firstWhere(
                            (tab) => tab.tab == _selectedTab,
                            orElse: () => tabs.first,
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

  List<_ProfileTabData> _tabs(BuildContext context) {
    return [
      _ProfileTabData(
        tab: _ProfileTab.leaderboards,
        asset: DuelAsset.leaderboardCrownPro,
        title: context.tr('leaderboards'),
        subtitle: context.tr('home_rating_label'),
        accent: const Color(0xFFB7A9FF),
        onOpen: () => _open(const LeaderboardsScreen()),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        _ProfileTabData(
          tab: _ProfileTab.platform,
          asset: DuelAsset.profilePro,
          title: Platform.isIOS ? 'Game Center' : 'Google Play Games',
          subtitle: context.tr('leaderboards'),
          accent: const Color(0xFF29D398),
          onOpen: () => _open(const PlatformServicesScreen()),
        ),
    ];
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

class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<_ProfileTabData> tabs;
  final _ProfileTab selected;
  final ValueChanged<_ProfileTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final active = selected == tab.tab;
          return ChoiceChip(
            selected: active,
            onSelected: (_) => onSelected(tab.tab),
            avatar: DuelAssetIcon(tab.asset, size: 18),
            label: Text(tab.title),
            labelStyle: TextStyle(
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: .72),
              fontWeight: FontWeight.w900,
            ),
            selectedColor: tab.accent.withValues(alpha: .24),
            backgroundColor: const Color(0xFF101B20).withValues(alpha: .9),
            side: BorderSide(color: tab.accent.withValues(alpha: .28)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileTabData {
  const _ProfileTabData({
    required this.tab,
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onOpen,
  });

  final _ProfileTab tab;
  final String asset;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onOpen;
}

class _ProfileTabPanel extends StatelessWidget {
  const _ProfileTabPanel({required this.tab});

  final _ProfileTabData tab;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tab.onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101B20).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tab.accent.withValues(alpha: .28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: tab.accent.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: DuelAssetIcon(tab.asset, size: 36),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tab.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .62),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: tab.accent),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _body(context),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _body(BuildContext context) {
    return switch (tab.tab) {
      _ProfileTab.leaderboards => context.tr('home_rating_label'),
      _ProfileTab.platform => tab.title,
    };
  }
}
