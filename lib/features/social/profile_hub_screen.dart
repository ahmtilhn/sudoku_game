import 'dart:io';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
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
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                      children: [
                        InPageHeader(title: context.tr('profile')),
                        if (_profile != null) ...[
                          CompetitiveProfileCard(profile: _profile!),
                        ],
                        if (_error != null)
                          _ProfileNotice(message: _error!, onRetry: _load),
                        const SizedBox(height: 10),
                        _ProfileActionGrid(
                          tabs: tabs,
                          selected: _selectedTab,
                          onSelected: (value) =>
                              setState(() => _selectedTab = value),
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
        metric: '9x9 / 16x16',
        onOpen: () => _open(const LeaderboardsScreen()),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        _ProfileTabData(
          tab: _ProfileTab.platform,
          asset: DuelAsset.profilePro,
          title: Platform.isIOS ? 'Game Center' : 'Google Play Games',
          subtitle: context.tr('leaderboards'),
          accent: const Color(0xFF29D398),
          metric: Platform.isIOS ? 'Native' : 'Play Games',
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

class _ProfileTabData {
  const _ProfileTabData({
    required this.tab,
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.metric,
    required this.onOpen,
  });

  final _ProfileTab tab;
  final String asset;
  final String title;
  final String subtitle;
  final Color accent;
  final String metric;
  final VoidCallback onOpen;
}

class _ProfileActionGrid extends StatelessWidget {
  const _ProfileActionGrid({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<_ProfileTabData> tabs;
  final _ProfileTab selected;
  final ValueChanged<_ProfileTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 2 : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 9)) / columns;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .055)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final tab in tabs)
                  SizedBox(
                    width: width,
                    child: _ProfileActionCard(
                      tab: tab,
                      selected: selected == tab.tab,
                      onSelected: () => onSelected(tab.tab),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileActionCard extends StatelessWidget {
  const _ProfileActionCard({
    required this.tab,
    required this.selected,
    required this.onSelected,
  });

  final _ProfileTabData tab;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          onSelected();
          tab.onOpen();
        },
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: tab.accent.withValues(alpha: selected ? .10 : .06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: tab.accent.withValues(alpha: selected ? .36 : .16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tab.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: tab.accent.withValues(alpha: .14)),
                ),
                child: DuelAssetIcon(tab.asset, size: 31),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tab.subtitle,
                      maxLines: 1,
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tab.accent.withValues(alpha: .18)),
                ),
                child: Text(
                  tab.metric,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tab.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: tab.accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
