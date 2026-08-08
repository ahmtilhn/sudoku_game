import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
import '../duel/leaderboards_screen.dart';
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
    final platformPlayer = _games.localPlayer.value;
    var discoverable = current.discoverable;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = username.text.trim().toLowerCase();
          final displayName = display.text.trim();
          final usernameStarted = username.text.trim().isNotEmpty;
          final displayStarted = displayName.isNotEmpty;
          final usernameValid = RegExp(
            r'^[a-z0-9_]{3,20}$',
          ).hasMatch(normalized);
          final valid =
              displayName.length >= 2 &&
              usernameValid;
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 20,
            ),
            backgroundColor: const Color(0xFF07111E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  16,
                  18,
                  18 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A1728),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFF7A5CFF,
                            ).withValues(alpha: .35),
                          ),
                        ),
                        child: Row(
                          children: [
                            PlayerAvatar(
                              displayName: displayName.isEmpty
                                  ? current.displayName
                                  : displayName,
                              avatarKey: current.avatarUrl ?? current.publicId,
                              localAvatarBytes: platformPlayer?.avatarBytes,
                              remoteApprovedImageUrl:
                                  platformPlayer?.avatarUrl ??
                                  current.avatarUrl,
                              radius: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('edit_player_profile'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      height: 1.05,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    context.tr('profile_edit_preview_body'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: .62,
                                      ),
                                      fontSize: 11,
                                      height: 1.2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: context.tr('cancel'),
                              onPressed: saving
                                  ? null
                                  : () => Navigator.of(
                                      dialogContext,
                                    ).pop(false),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: display,
                        maxLength: 24,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          prefixIcon: const Icon(Icons.badge_rounded),
                          labelText: context.tr('shown_to_other_players'),
                          hintText: context.tr('display_name'),
                          helperText: context.tr('profile_display_helper'),
                          errorText: displayStarted && displayName.length < 2
                              ? context.tr('profile_display_error')
                              : null,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: .06),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: username,
                        maxLength: 20,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                          labelText: context.tr('profile_search_name'),
                          hintText: 'sudoku_master',
                          helperText: context.tr('profile_search_helper'),
                          errorText: usernameStarted && !usernameValid
                              ? context.tr('profile_search_error')
                              : null,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: .06),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .1),
                          ),
                        ),
                        child: SwitchListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          secondary: const Icon(Icons.search_rounded),
                          title: Text(
                            context.tr('profile_discovery_title'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(
                            discoverable
                                ? context.tr('profile_discovery_on')
                                : context.tr('profile_discovery_off'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .6),
                            ),
                          ),
                          value: discoverable,
                          onChanged: saving
                              ? null
                              : (value) => setDialogState(
                                  () => discoverable = value,
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.of(
                                      dialogContext,
                                    ).pop(false),
                              child: Text(context.tr('cancel')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: !valid || saving
                                  ? null
                                  : () async {
                                      setDialogState(() => saving = true);
                                      try {
                                        await _preferencesService.update(
                                          username: normalized,
                                          displayName: displayName,
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
                                          title: context.tr(
                                            'edit_player_profile',
                                          ),
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
                                  : const Icon(Icons.check_rounded),
                              label: Text(context.tr('save')),
                            ),
                          ),
                        ],
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
                          avatarBytes: platformPlayer?.avatarBytes,
                          rankName: profile?.rankName,
                          connected: platformPlayer != null,
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 7 : 10),
                        SizedBox(
                          height: compact ? 42 : 46,
                          child: SegmentedButton<_ProfileTab>(
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
                              visualDensity: VisualDensity.compact,
                              textStyle: WidgetStatePropertyAll(
                                TextStyle(fontSize: compact ? 11 : 12),
                              ),
                            ),
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
    required Uint8List? avatarBytes,
    required String? rankName,
    required bool connected,
    required bool compact,
  }) {
    return Container(
      key: const ValueKey<String>('profile-identity-card'),
      height: compact ? 88 : 98,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 13,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(18),
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
            localAvatarBytes: avatarBytes,
            remoteApprovedImageUrl: avatarUrl,
            radius: compact ? 27 : 31,
            semanticLabel: context.tr(
              'player_avatar_semantics',
              <Object>[displayName],
            ),
          ),
          SizedBox(width: compact ? 9 : 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 17 : 20,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB7A9FF),
                      fontSize: 11,
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
                      fontSize: 9.5,
                      height: 1.1,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Container(
            constraints: const BoxConstraints(minWidth: 60, maxWidth: 92),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
              color: (connected ? const Color(0xFF29D398) : Colors.white)
                  .withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (connected
                        ? const Color(0xFF29D398)
                        : Colors.white38)
                    .withValues(alpha: .4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connected ? Icons.verified_rounded : Icons.link_off_rounded,
                  color: connected
                      ? const Color(0xFF29D398)
                      : Colors.white38,
                  size: 18,
                ),
                if (rankName != null && rankName.trim().isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      rankName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFC73D),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
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
    final metrics = <_MetricData>[
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
    ];
    return LayoutBuilder(
      key: const ValueKey<String>('profile-overview'),
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _compactMetricGrid(metrics, columns: columns),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1728).withValues(alpha: .94),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: const Color(0xFFFFC73D).withValues(alpha: .32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const DuelAssetIcon(
                        DuelAsset.resultVictoryTrophyPro,
                        size: 29,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          context.tr('achievement_showcase'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
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
                  const SizedBox(height: 9),
                  if (achievements.isEmpty)
                    Text(
                      context.tr('achievement_showcase_empty'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                        fontSize: 11,
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
                            const SizedBox(width: 6),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _performance(CompetitiveProfile? profile) {
    if (profile == null) return _emptyState();
    final metrics = <_MetricData>[
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
    ];
    return LayoutBuilder(
      key: const ValueKey<String>('profile-performance'),
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 2;
        return GridView.builder(
          padding: EdgeInsets.zero,
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 88,
          ),
          itemBuilder: (context, index) => _metricTile(metrics[index]),
        );
      },
    );
  }

  Widget _account(bool platformConnected) {
    final actions = <_AccountData>[
      _AccountData(
        context.tr('leaderboards'),
        context.tr('global_elo'),
        DuelAsset.leaderboardCrownPro,
        () => _open(const LeaderboardsScreen()),
      ),
      _AccountData(
        context.tr('friends_challenges'),
        context.tr('friend_requests'),
        DuelAsset.homeFriendsScene,
        () => _open(const SocialHubScreen()),
      ),
      _AccountData(
        context.tr('coin_history'),
        context.tr('server_wallet_history'),
        DuelAsset.walletCoinStackPro,
        () => _open(const WalletHistoryScreen()),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        _AccountData(
          Platform.isIOS ? 'Game Center' : 'Google Play Games',
          platformConnected
              ? UxCopy.connectedPlatform(context)
              : UxCopy.platformNotConnected(context),
          DuelAsset.homeProfileScene,
          () => _open(const PlatformServicesScreen()),
        ),
    ];
    return LayoutBuilder(
      key: const ValueKey<String>('profile-account'),
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 3
            : constraints.maxWidth >= 460
            ? 2
            : 1;
        return GridView.builder(
          padding: EdgeInsets.zero,
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 84,
          ),
          itemBuilder: (context, index) => _AccountTile(actions[index]),
        );
      },
    );
  }

  Widget _compactMetricGrid(
    List<_MetricData> metrics, {
    required int columns,
  }) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 84,
      ),
      itemBuilder: (context, index) => _metricTile(metrics[index]),
    );
  }

  Widget _metricTile(_MetricData value) {
    return UxMetricTile(
      label: value.label,
      value: value.value,
      icon: value.icon,
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC73D).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFC73D).withValues(alpha: .3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            color: Color(0xFFFFC73D),
            size: 18,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1.1,
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
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1728).withValues(alpha: .94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .13)),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF07111E).withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: DuelAssetIcon(data.asset, size: 44),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .55),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: .45),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
