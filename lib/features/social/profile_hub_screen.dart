import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../localization/ux_copy.dart';
import '../../services/platform_game_services.dart';
import '../../services/player_profile_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/ux_feedback.dart';
import '../economy/wallet_history_screen.dart';
import 'platform_services_screen.dart';
import 'social_hub_screen.dart';

enum _ProfileTab { overview, performance, account }

class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({super.key});

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  final PlatformGameServices _games = PlatformGameServices.instance;
  final PlayerProfileService _preferencesService =
      PlayerProfileService.instance;

  CompetitiveProfile? _profile;
  PlayerProfilePreferences? _preferences;
  _ProfileTab _tab = _ProfileTab.overview;
  bool _loading = true;
  bool _showingError = false;

  @override
  void initState() {
    super.initState();
    _games.localPlayer.addListener(_onIdentityChanged);
    _preferencesService.current.addListener(_onIdentityChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _games.localPlayer.removeListener(_onIdentityChanged);
    _preferencesService.current.removeListener(_onIdentityChanged);
    super.dispose();
  }

  void _onIdentityChanged() {
    if (!mounted) return;
    setState(() {
      _preferences = _preferencesService.current.value ?? _preferences;
    });
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) setState(() => _loading = true);
    Object? failure;
    try {
      _preferences = await _preferencesService.load();
    } catch (error) {
      failure = error;
    }
    try {
      _profile = await SocialApiClient.instance.loadCompetitiveProfile();
    } catch (error) {
      failure ??= error;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (failure != null && !_showingError) {
      _showingError = true;
      final retry = await GameModal.error(
        context,
        title: context.tr('profile'),
        message: UserSafeError.message(context, failure),
        retryLabel: context.tr('retry'),
        cancelLabel: context.tr('cancel'),
      );
      _showingError = false;
      if (retry == true && mounted) unawaited(_load());
    }
  }

  Future<void> _editProfile() async {
    final current = _preferences;
    if (current == null) return;
    final display = TextEditingController(text: current.displayName);
    final username = TextEditingController(text: current.username);
    var discoverable = current.discoverable;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = username.text.trim().toLowerCase();
          final valid =
              display.text.trim().length >= 2 &&
              RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalized);
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 20,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  18 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('edit_player_profile'),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(
                                    dialogContext,
                                  ).pop(false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: display,
                        maxLength: 24,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.tr('display_name'),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: username,
                        maxLength: 20,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: context.tr('unique_username'),
                          helperText: context.tr('username_helper'),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.tr('discoverable_by_players')),
                        subtitle: Text(
                          context.tr('discoverable_by_players_body'),
                        ),
                        value: discoverable,
                        onChanged: saving
                            ? null
                            : (value) => setDialogState(
                                () => discoverable = value,
                              ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: !valid || saving
                            ? null
                            : () async {
                                setDialogState(() => saving = true);
                                try {
                                  await _preferencesService.update(
                                    username: normalized,
                                    displayName: display.text.trim(),
                                    discoverable: discoverable,
                                    nameSource: 'custom',
                                  );
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop(true);
                                  }
                                } catch (error) {
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() => saving = false);
                                  await GameModal.error(
                                    dialogContext,
                                    title: context.tr('edit_player_profile'),
                                    message: UserSafeError.message(
                                      dialogContext,
                                      error,
                                    ),
                                    retryLabel: context.tr('try_again'),
                                    cancelLabel: context.tr('cancel'),
                                  );
                                }
                              },
                        icon: saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(context.tr('save')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    display.dispose();
    username.dispose();
    if (saved == true) await _load(showSpinner: false);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (mounted) await _load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final platformPlayer = _games.localPlayer.value;
    final profile = _profile;
    final preferences = _preferences;
    final displayName = preferences?.displayName.trim().isNotEmpty == true
        ? preferences!.displayName
        : profile?.displayName ??
              platformPlayer?.displayName ??
              'Sudoku Player';
    final username = preferences?.username.trim().isNotEmpty == true
        ? preferences!.username
        : profile?.username ?? '';
    final publicId = preferences?.publicId.trim().isNotEmpty == true
        ? preferences!.publicId
        : profile?.publicId ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      compact ? 6 : 10,
                      14,
                      compact ? 8 : 14,
                    ),
                    child: Column(
                      children: [
                        _header(),
                        SizedBox(height: compact ? 7 : 10),
                        _identityCard(
                          displayName: displayName,
                          username: username,
                          publicId: publicId,
                          avatarKey: profile?.avatarKey ?? 'default',
                          avatarUrl: platformPlayer?.avatarUrl,
                          rankName: profile?.rankName,
                          connected: platformPlayer != null,
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 7 : 10),
                        SegmentedButton<_ProfileTab>(
                          segments: [
                            ButtonSegment<_ProfileTab>(
                              value: _ProfileTab.overview,
                              icon: const Icon(Icons.dashboard_rounded),
                              label: Text(UxCopy.overview(context)),
                            ),
                            ButtonSegment<_ProfileTab>(
                              value: _ProfileTab.performance,
                              icon: const Icon(Icons.query_stats_rounded),
                              label: Text(UxCopy.performance(context)),
                            ),
                            ButtonSegment<_ProfileTab>(
                              value: _ProfileTab.account,
                              icon: const Icon(
                                Icons.manage_accounts_rounded,
                              ),
                              label: Text(
                                UxCopy.accountAndSocial(context),
                              ),
                            ),
                          ],
                          selected: <_ProfileTab>{_tab},
                          onSelectionChanged: (value) =>
                              setState(() => _tab = value.first),
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            visualDensity: compact
                                ? VisualDensity.compact
                                : VisualDensity.standard,
                          ),
                        ),
                        SizedBox(height: compact ? 7 : 10),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _tabContent(
                                    profile,
                                    platformPlayer != null,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('profile'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: context.tr('edit_player_profile'),
            onPressed: _preferences == null ? null : _editProfile,
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.edit_rounded, size: 20),
          ),
          const SizedBox(width: 5),
          IconButton.filledTonal(
            tooltip: context.tr('refresh'),
            onPressed: _loading ? null : _load,
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _identityCard({
    required String displayName,
    required String username,
    required String publicId,
    required String avatarKey,
    required String? avatarUrl,
    required String? rankName,
    required bool connected,
    required bool compact,
  }) {
    return Container(
      key: const ValueKey<String>('profile-identity-card'),
      height: compact ? 92 : 104,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 11 : 14,
        vertical: compact ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: const Color(0xFF7A5CFF).withValues(alpha: .48),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PlayerAvatar(
            displayName: displayName,
            avatarKey: avatarKey,
            remoteApprovedImageUrl: avatarUrl,
            radius: compact ? 29 : 34,
            semanticLabel: context.tr(
              'player_avatar_semantics',
              <Object>[displayName],
            ),
          ),
          SizedBox(width: compact ? 10 : 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  strutStyle: const StrutStyle(
                    forceStrutHeight: true,
                    height: 1.05,
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 18 : 21,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB7A9FF),
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (publicId.isNotEmpty)
                  Text(
                    context.tr('friend_id_value', <Object>[publicId]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .52),
                      fontSize: 10,
                      height: 1.1,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: compact ? 68 : 78,
              maxWidth: compact ? 88 : 110,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: (connected
                        ? const Color(0xFF29D398)
                        : Colors.white)
                    .withValues(alpha: .1),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: (connected
                          ? const Color(0xFF29D398)
                          : Colors.white38)
                      .withValues(alpha: .42),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connected
                        ? Icons.verified_rounded
                        : Icons.link_off_rounded,
                    color: connected
                        ? const Color(0xFF29D398)
                        : Colors.white38,
                    size: 20,
                  ),
                  if (rankName != null && rankName.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      rankName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFC73D),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabContent(
    CompetitiveProfile? profile,
    bool platformConnected,
  ) {
    return switch (_tab) {
      _ProfileTab.overview => _overview(profile),
      _ProfileTab.performance => _performance(profile),
      _ProfileTab.account => _account(platformConnected),
    };
  }

  Widget _overview(CompetitiveProfile? profile) {
    if (profile == null) return _emptyState();
    final achievements = profile.achievementShowcase.take(3).toList();
    return Column(
      key: const ValueKey<String>('profile-overview'),
      children: [
        Expanded(
          flex: 3,
          child: _metricGrid([
            _MetricData(
              context.tr('current_elo'),
              '${profile.currentElo}',
              Icons.bolt_rounded,
            ),
            _MetricData(
              context.tr('rank'),
              profile.rank == null ? '—' : '#${profile.rank}',
              Icons.public_rounded,
            ),
            _MetricData(
              context.tr('season_peak'),
              '${profile.seasonPeak}',
              Icons.trending_up_rounded,
            ),
            _MetricData(
              context.tr('country'),
              profile.country?.isNotEmpty == true
                  ? profile.country!
                  : context.tr('country_not_set'),
              Icons.flag_rounded,
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728).withValues(alpha: .94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFFC73D).withValues(alpha: .35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFFC73D),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('achievement_showcase'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${profile.achievementCount}',
                      style: const TextStyle(
                        color: Color(0xFFFFC73D),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (achievements.isEmpty)
                  Center(
                    child: Text(
                      context.tr('achievement_showcase_empty'),
                    ),
                  )
                else
                  Row(
                    children: [
                      for (
                        var index = 0;
                        index < achievements.length;
                        index++
                      ) ...[
                        Expanded(
                          child: _AchievementBadge(
                            title: achievements[index].title,
                          ),
                        ),
                        if (index != achievements.length - 1)
                          const SizedBox(width: 7),
                      ],
                    ],
                  ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _performance(CompetitiveProfile? profile) {
    if (profile == null) return _emptyState();
    return _metricGrid(
      [
        _MetricData(
          UxCopy.totalMatches(context),
          '${profile.wins + profile.losses + profile.draws}',
          Icons.sports_esports_rounded,
        ),
        _MetricData(
          context.tr('wins_losses_draws'),
          '${profile.wins}/${profile.losses}/${profile.draws}',
          Icons.scoreboard_rounded,
        ),
        _MetricData(
          context.tr('win_rate'),
          '${(profile.winRate * 100).round()}%',
          Icons.percent_rounded,
        ),
        _MetricData(
          context.tr('win_streak'),
          '${profile.winStreak}',
          Icons.local_fire_department_rounded,
        ),
        _MetricData(
          context.tr('tournament_entries'),
          '${profile.tournamentEntries}',
          Icons.stadium_rounded,
        ),
        _MetricData(
          context.tr('tournament_podiums'),
          '${profile.tournamentPodiums}',
          Icons.emoji_events_rounded,
        ),
      ],
      key: const ValueKey<String>('profile-performance'),
    );
  }

  Widget _account(bool platformConnected) {
    final actions = <_AccountData>[
      _AccountData(
        context.tr('friends_challenges'),
        context.tr('friend_requests'),
        DuelAsset.friendsPro,
        () => _open(const SocialHubScreen()),
      ),
      _AccountData(
        context.tr('coin_history'),
        context.tr('server_wallet_history'),
        DuelAsset.storePro,
        () => _open(const WalletHistoryScreen()),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        _AccountData(
          Platform.isIOS ? 'Game Center' : 'Google Play Games',
          platformConnected
              ? UxCopy.connectedPlatform(context)
              : UxCopy.platformNotConnected(context),
          DuelAsset.profilePro,
          () => _open(const PlatformServicesScreen()),
        ),
    ];
    return LayoutBuilder(
      key: const ValueKey<String>('profile-account'),
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 1;
        final rows = (actions.length / columns).ceil();
        final gap = 10.0;
        final extent =
            (constraints.maxHeight - gap * (rows - 1)) / rows;
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: extent,
          ),
          itemBuilder: (context, index) => _AccountTile(actions[index]),
        );
      },
    );
  }

  Widget _metricGrid(List<_MetricData> metrics, {Key? key}) {
    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 2;
        final rows = (metrics.length / columns).ceil();
        final gap = 9.0;
        final extent =
            (constraints.maxHeight - gap * (rows - 1)) / rows;
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: extent,
          ),
          itemBuilder: (context, index) {
            final value = metrics[index];
            return UxMetricTile(
              label: value.label,
              value: value.value,
              icon: value.icon,
            );
          },
        );
      },
    );
  }

  Widget _emptyState() {
    return UxStatePanel(
      icon: Icons.cloud_off_rounded,
      title: context.tr('profile'),
      message: context.tr('try_again_when_connected'),
      actionLabel: context.tr('retry'),
      onAction: _load,
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC73D).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFC73D).withValues(alpha: .32),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            color: Color(0xFFFFC73D),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountData {
  const _AccountData(
    this.title,
    this.subtitle,
    this.asset,
    this.onTap,
  );

  final String title;
  final String subtitle;
  final String asset;
  final VoidCallback onTap;
}

class _AccountTile extends StatelessWidget {
  const _AccountTile(this.data);

  final _AccountData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1728).withValues(alpha: .94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: .13),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: DuelAssetIcon(data.asset, size: 88)),
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  data.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
