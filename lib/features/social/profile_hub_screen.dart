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
    final platformPlayer = _games.localPlayer.value;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        InPageHeader(title: context.tr('profile')),
                        if (_profile != null) ...[
                          CompetitiveProfileCard(profile: _profile!),
                          const SizedBox(height: 12),
                          _ProfileQuickStats(
                            profile: _profile!,
                            platformPlayer: platformPlayer,
                          ),
                        ],
                        if (_error != null)
                          _ProfileNotice(message: _error!, onRetry: _load),
                        const SizedBox(height: 12),
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

class _ProfileQuickStats extends StatelessWidget {
  const _ProfileQuickStats({
    required this.profile,
    required this.platformPlayer,
  });

  final CompetitiveProfile profile;
  final PlatformPlayer? platformPlayer;

  @override
  Widget build(BuildContext context) {
    final games = profile.wins + profile.losses + profile.draws;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: itemWidth,
              child: _MetricTile(
                label: context.tr('current_elo'),
                value: '${profile.currentElo}',
                asset: DuelAsset.leaderboardCrownPro,
                color: const Color(0xFF3AA9FF),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _MetricTile(
                label: context.tr('wins_losses_draws'),
                value: '${profile.wins}/${profile.losses}/${profile.draws}',
                asset: DuelAsset.trophy,
                color: const Color(0xFF29D398),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _MetricTile(
                label: platformPlayer == null ? 'Account' : 'Platform',
                value: platformPlayer == null ? '$games games' : 'Linked',
                asset: DuelAsset.profilePro,
                color: const Color(0xFFB7A9FF),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.asset,
    required this.color,
  });

  final String label;
  final String value;
  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DuelAssetIcon(asset, size: 20, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .58),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
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
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? .065 : .04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: tab.accent.withValues(alpha: selected ? .46 : .22),
            ),
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
              const SizedBox(height: 12),
              Text(
                tab.metric,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tab.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
