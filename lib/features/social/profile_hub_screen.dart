import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../models/rank_identity_models.dart';
import '../../services/platform_game_services.dart';
import '../../services/rank_identity_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
import '../duel/leaderboards_screen.dart';
import 'emote_loadout_screen.dart';
import 'platform_services_screen.dart';
import 'profile_customization_screen.dart';
import 'rank_identity_summary_card.dart';

enum _ProfileTab { customize, emotes, leaderboards, platform }

class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({super.key});

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  final PlatformGameServices _games = PlatformGameServices.instance;
  final RankIdentityService _rankIdentity = RankIdentityService.instance;

  RankIdentityProfile? _profile;
  bool _loading = true;
  String? _error;
  _ProfileTab _selectedTab = _ProfileTab.customize;

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
      // The in-game profile remains usable without native platform identity.
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _rankIdentity.refresh();
      if (mounted) setState(() => _profile = value);
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget screen, {bool refreshAfter = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (refreshAfter && mounted) await _load();
  }

  Future<void> _openCustomization() => _open(
        const ProfileCustomizationScreen(),
        refreshAfter: true,
      );

  Future<void> _openEmotes() => _open(const EmoteLoadoutScreen());

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
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading && _profile == null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 220),
                          Center(child: CircularProgressIndicator()),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                        children: [
                          InPageHeader(
                            title: context.tr('profile'),
                            actions: [
                              IconButton(
                                tooltip: context.tr('refresh'),
                                onPressed: _loading ? null : _load,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                          if (_profile != null)
                            RankIdentitySummaryCard(
                              profile: _profile!,
                              onCustomize: _openCustomization,
                            ),
                          if (_error != null)
                            _ProfileNotice(message: _error!, onRetry: _load),
                          const SizedBox(height: 12),
                          _ProfileActionGrid(
                            tabs: tabs,
                            selected: _selectedTab,
                            onSelected: (value) =>
                                setState(() => _selectedTab = value),
                          ),
                          if (_profile != null) ...[
                            const SizedBox(height: 12),
                            _IdentityPolicyNote(profile: _profile!),
                          ],
                        ],
                      ),
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
        tab: _ProfileTab.customize,
        asset: DuelAsset.profilePro,
        title: 'Profile style',
        subtitle: 'Avatar, rank frame, badges and title',
        accent: const Color(0xFF66C7FF),
        metric: '96 avatars',
        onOpen: _openCustomization,
      ),
      _ProfileTabData(
        tab: _ProfileTab.emotes,
        asset: DuelAsset.homeDuelEmblem,
        title: 'Emotes',
        subtitle: 'Choose and order your 8 quick duel emotes',
        accent: const Color(0xFFFFC94D),
        metric: '8 slots',
        onOpen: _openEmotes,
      ),
      _ProfileTabData(
        tab: _ProfileTab.leaderboards,
        asset: DuelAsset.leaderboardCrownPro,
        title: context.tr('leaderboards'),
        subtitle: 'Rank Points and division progress',
        accent: const Color(0xFFB7A9FF),
        metric: '${_profile?.rankPoints ?? 0} RP',
        onOpen: () => _open(const LeaderboardsScreen(), refreshAfter: true),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        _ProfileTabData(
          tab: _ProfileTab.platform,
          asset: DuelAsset.profilePro,
          title: Platform.isIOS ? 'Game Center' : 'Google Play Games',
          subtitle: 'Native platform services',
          accent: const Color(0xFF29D398),
          metric: Platform.isIOS ? 'Native' : 'Play Games',
          onOpen: () => _open(const PlatformServicesScreen()),
        ),
    ];
  }
}

class _IdentityPolicyNote extends StatelessWidget {
  const _IdentityPolicyNote({required this.profile});

  final RankIdentityProfile profile;

  @override
  Widget build(BuildContext context) {
    final selectedBadges = profile.selectedDecorationKeys.length;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .055)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF29D398),
            size: 23,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Rank frames and achievement badges are earned, not purchased. '
              'You can equip up to 3 earned badges on your frame. '
              '$selectedBadges/3 badge slots are currently in use.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .60),
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
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
