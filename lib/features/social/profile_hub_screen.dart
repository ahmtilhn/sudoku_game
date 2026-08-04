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
import '../../widgets/player_avatar.dart';
import '../../widgets/ux_feedback.dart';
import '../economy/wallet_history_screen.dart';
import 'platform_services_screen.dart';
import 'social_hub_screen.dart';

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
  bool _loading = true;
  String? _errorMessage;

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
    if (showSpinner) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

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
    setState(() {
      _loading = false;
      _errorMessage = failure == null
          ? null
          : UserSafeError.message(context, failure);
    });
  }

  Future<void> _editProfile() async {
    final current = _preferences;
    if (current == null) return;
    final display = TextEditingController(text: current.displayName);
    final username = TextEditingController(text: current.username);
    var discoverable = current.discoverable;
    var saving = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final normalized = username.text.trim().toLowerCase();
          final valid = display.text.trim().length >= 2 &&
              RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalized);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('edit_player_profile'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: display,
                    maxLength: 24,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: context.tr('display_name'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 8),
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
                    onChanged: (_) => setSheetState(() {}),
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
                        : (value) =>
                            setSheetState(() => discoverable = value),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: !valid || saving
                        ? null
                        : () async {
                            setSheetState(() => saving = true);
                            try {
                              await _preferencesService.update(
                                username: normalized,
                                displayName: display.text.trim(),
                                discoverable: discoverable,
                                nameSource: 'custom',
                              );
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop(true);
                              }
                            } catch (error) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() => saving = false);
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    UserSafeError.message(sheetContext, error),
                                  ),
                                ),
                              );
                            }
                          },
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(context.tr('save')),
                  ),
                ],
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

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final platformPlayer = _games.localPlayer.value;
    final profile = _profile;
    final preferences = _preferences;
    final displayName = preferences?.displayName.trim().isNotEmpty == true
        ? preferences!.displayName
        : profile?.displayName ?? platformPlayer?.displayName ?? 'Sudoku Player';
    final username = preferences?.username.trim().isNotEmpty == true
        ? preferences!.username
        : profile?.username ?? '';
    final publicId = preferences?.publicId.trim().isNotEmpty == true
        ? preferences!.publicId
        : profile?.publicId ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('profile')),
        actions: [
          IconButton(
            tooltip: context.tr('edit_player_profile'),
            onPressed: preferences == null ? null : _editProfile,
            icon: const Icon(Icons.edit_outlined),
          ),
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
          child: RefreshIndicator(
            onRefresh: _load,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _IdentityHeader(
                      displayName: displayName,
                      username: username,
                      publicId: publicId,
                      avatarKey: profile?.avatarKey ?? 'default',
                      avatarUrl: platformPlayer?.avatarUrl,
                      rankName: profile?.rankName,
                      platformConnected: platformPlayer != null,
                      onEdit: preferences == null ? null : _editProfile,
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      UxStatePanel(
                        icon: Icons.sync_rounded,
                        title: UxCopy.loading(context),
                        message: UxCopy.loading(context),
                        compact: true,
                      )
                    else if (_errorMessage != null)
                      UxStatePanel.error(
                        context,
                        message: _errorMessage!,
                        onRetry: _load,
                      ),
                    if (profile != null) ...[
                      const SizedBox(height: 16),
                      _SectionTitle(
                        icon: Icons.public_rounded,
                        title: UxCopy.overview(context),
                      ),
                      const SizedBox(height: 8),
                      _MetricGrid(
                        children: [
                          UxMetricTile(
                            label: context.tr('current_elo'),
                            value: '${profile.currentElo}',
                            icon: Icons.bolt_rounded,
                          ),
                          UxMetricTile(
                            label: context.tr('rank'),
                            value: profile.rank == null ? '—' : '#${profile.rank}',
                            icon: Icons.public_rounded,
                          ),
                          UxMetricTile(
                            label: context.tr('season_peak'),
                            value: '${profile.seasonPeak}',
                            icon: Icons.trending_up_rounded,
                          ),
                          UxMetricTile(
                            label: context.tr('country'),
                            value: profile.country?.isNotEmpty == true
                                ? profile.country!
                                : context.tr('country_not_set'),
                            icon: Icons.flag_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        icon: Icons.query_stats_rounded,
                        title: UxCopy.performance(context),
                      ),
                      const SizedBox(height: 8),
                      _MetricGrid(
                        children: [
                          UxMetricTile(
                            label: UxCopy.totalMatches(context),
                            value:
                                '${profile.wins + profile.losses + profile.draws}',
                            icon: Icons.sports_esports_rounded,
                          ),
                          UxMetricTile(
                            label: context.tr('wins_losses_draws'),
                            value:
                                '${profile.wins}/${profile.losses}/${profile.draws}',
                            icon: Icons.scoreboard_outlined,
                          ),
                          UxMetricTile(
                            label: context.tr('win_rate'),
                            value: '${(profile.winRate * 100).round()}%',
                            icon: Icons.percent_rounded,
                          ),
                          UxMetricTile(
                            label: context.tr('win_streak'),
                            value: '${profile.winStreak}',
                            icon: Icons.local_fire_department_rounded,
                          ),
                          UxMetricTile(
                            label: context.tr('tournament_entries'),
                            value: '${profile.tournamentEntries}',
                            icon: Icons.stadium_outlined,
                          ),
                          UxMetricTile(
                            label: context.tr('tournament_podiums'),
                            value: '${profile.tournamentPodiums}',
                            icon: Icons.emoji_events_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _AchievementSection(profile: profile),
                    ],
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.manage_accounts_outlined,
                      title: UxCopy.accountAndSocial(context),
                    ),
                    const SizedBox(height: 8),
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
                        subtitle: platformPlayer == null
                            ? UxCopy.platformNotConnected(context)
                            : UxCopy.connectedPlatform(context),
                        trailing: platformPlayer == null
                            ? Icons.link_off_rounded
                            : Icons.verified_rounded,
                        onTap: () => _open(const PlatformServicesScreen()),
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

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({
    required this.displayName,
    required this.username,
    required this.publicId,
    required this.avatarKey,
    required this.avatarUrl,
    required this.rankName,
    required this.platformConnected,
    required this.onEdit,
  });

  final String displayName;
  final String username;
  final String publicId;
  final String avatarKey;
  final String? avatarUrl;
  final String? rankName;
  final bool platformConnected;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlayerAvatar(
                  displayName: displayName,
                  avatarKey: avatarKey,
                  remoteApprovedImageUrl: avatarUrl,
                  radius: 38,
                  semanticLabel: context.tr(
                    'player_avatar_semantics',
                    <Object>[displayName],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      if (username.isNotEmpty)
                        Text(
                          '@$username',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (publicId.isNotEmpty)
                        Text(
                          context.tr('friend_id_value', <Object>[publicId]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr('edit_player_profile'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    platformConnected
                        ? Icons.verified_rounded
                        : Icons.link_off_rounded,
                    size: 18,
                  ),
                  label: Text(
                    platformConnected
                        ? UxCopy.connectedPlatform(context)
                        : UxCopy.platformNotConnected(context),
                  ),
                ),
                if (rankName != null)
                  Chip(
                    avatar: const Icon(Icons.shield_outlined, size: 18),
                    label: Text(rankName!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620
            ? 4
            : constraints.maxWidth >= 400
                ? 2
                : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _AchievementSection extends StatelessWidget {
  const _AchievementSection({required this.profile});

  final CompetitiveProfile profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.emoji_events_outlined,
              title: context.tr('achievement_showcase'),
            ),
            const SizedBox(height: 10),
            Text(
              '${UxCopy.achievements(context)}: ${profile.achievementCount}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (profile.achievementShowcase.isEmpty)
              Text(context.tr('achievement_showcase_empty'))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final achievement in profile.achievementShowcase.take(3))
                    Chip(
                      avatar: const Icon(Icons.workspace_premium, size: 18),
                      label: Text(achievement.title),
                    ),
                ],
              ),
          ],
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
    this.trailing = Icons.chevron_right_rounded,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minTileHeight: 72,
        leading: Icon(icon, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: Icon(trailing),
        onTap: onTap,
      ),
    );
  }
}
