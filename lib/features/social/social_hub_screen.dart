import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/player_profile_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/responsive_layout.dart';
import 'challenge_waiting_screen.dart';
import 'ux_challenge_invitation_screen.dart';

class SocialHubScreen extends StatefulWidget {
  const SocialHubScreen({super.key});

  @override
  State<SocialHubScreen> createState() => _SocialHubScreenState();
}

class _SocialHubScreenState extends State<SocialHubScreen>
    with SingleTickerProviderStateMixin {
  final SocialApiClient _social = SocialApiClient.instance;
  final PushNotificationService _push = PushNotificationService.instance;
  final TextEditingController _search = TextEditingController();
  late final TabController _tabs;

  PlayerProfilePreferences? _me;
  List<SocialPlayer> _friends = const [];
  List<SocialPlayer> _requests = const [];
  List<SocialPlayer> _opponents = const [];
  List<SocialChallenge> _challenges = const [];
  List<SocialPlayer> _results = const [];
  bool _loading = true;
  bool _searching = false;
  bool _pushBusy = false;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    unawaited(_load());
    unawaited(_prepareNotifications());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  List<SocialChallenge> get _incoming {
    final id = _me?.publicId;
    return _challenges
        .where(
          (challenge) =>
              challenge.status == 'pending' &&
              challenge.recipient.publicId == id,
        )
        .toList(growable: false);
  }

  Future<void> _prepareNotifications() async {
    await _push.initialize();
    if (!_push.userDisabled.value) {
      await _push.refreshRegistration();
    }
    if (mounted) setState(() {});
  }

  Future<bool> _enableNotifications() async {
    if (_pushBusy) return _push.enabled.value;
    setState(() => _pushBusy = true);
    try {
      final enabled = await _push.requestPermissionAndRegister();
      if (!mounted) return enabled;
      if (!enabled) {
        _showSnack(
          _push.lastRegistrationError.value ??
              context.tr('challenge_notification_permission_denied'),
        );
      }
      return enabled;
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait<Object>([
        PlayerProfileService.instance.load(),
        _social.loadFriends(),
        _social.loadIncomingFriendRequests(),
        _social.loadPendingChallenges(),
        _social.loadRecentOpponents(),
      ]);
      if (!mounted) return;
      setState(() {
        _me = values[0] as PlayerProfilePreferences;
        _friends = values[1] as List<SocialPlayer>;
        _requests = values[2] as List<SocialPlayer>;
        _challenges = values[3] as List<SocialChallenge>;
        _opponents = values[4] as List<SocialPlayer>;
      });
    } catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _perform(String id, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _findPlayers() async {
    final query = _search.text.trim();
    if (query.length < 3 || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _social.searchPlayers(query);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendFriendRequest(SocialPlayer player) async {
    await _perform('friend-${player.publicId}', () async {
      await _social.sendFriendRequest(player.publicId);
    });
    if (!mounted || _error != null) return;
    _showSnack(context.tr('friend_request_sent'));
  }

  Future<void> _respondRequest(SocialPlayer player, bool accept) async {
    await _perform('request-${player.publicId}', () async {
      await _social.respondToFriendRequest(
        requesterPublicId: player.publicId,
        accept: accept,
      );
    });
    if (!mounted || _error != null || !accept) return;
    _showSnack(
      context.tr('friend_request_accepted', <Object>[player.displayName]),
    );
  }

  Future<void> _challenge(SocialPlayer player) async {
    final difficulty = await showAdaptiveBottomSheet<SudokuDifficulty>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('choose_duel_difficulty'),
              textAlign: TextAlign.center,
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final item in SudokuDifficulty.values)
              ListTile(
                minTileHeight: 54,
                leading: DuelAssetIcon(
                  DuelAsset.grid,
                  size: 24,
                  color: _accent(item),
                ),
                title: Text(context.strings.difficultyLabel(item)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(sheetContext).pop(item),
              ),
          ],
        ),
      ),
    );
    if (difficulty == null || _busyId != null) return;

    if (!_push.enabled.value && !_push.userDisabled.value) {
      await _enableNotifications();
      if (!mounted) return;
    }

    setState(() {
      _busyId = 'challenge-${player.publicId}';
      _error = null;
    });
    try {
      final challenge = await _social.createChallenge(
        recipientPublicId: player.publicId,
        difficulty: difficulty.name,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChallengeWaitingScreen(challenge: challenge),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted)
        setState(() => _error = UserSafeError.message(context, error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openChallenge(SocialChallenge challenge) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UxChallengeInvitationScreen(challengeId: challenge.id),
      ),
    );
    if (mounted) await _load();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ResponsiveMetrics.of(context);
    final searchMaxHeight = metrics.keyboardVisible
        ? (metrics.height * 0.48).clamp(190.0, 330.0)
        : (metrics.height * 0.54).clamp(220.0, 460.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('friends_challenges')),
        actions: [
          IconButton(
            tooltip: context.tr('refresh'),
            onPressed: _loading ? null : _load,
            icon: const DuelAssetIcon(DuelAsset.refresh, size: 22),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: '${context.tr('friend_requests')} (${_requests.length})'),
            Tab(text: '${context.tr('friends')} (${_friends.length})'),
            Tab(text: '${context.tr('challenge')} (${_incoming.length})'),
            Tab(text: context.tr('opponent')),
          ],
        ),
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: searchMaxHeight),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ResponsiveConstrainedContent(
                    maxWidth: 680,
                    padding: EdgeInsets.fromLTRB(
                      metrics.pagePadding,
                      12,
                      metrics.pagePadding,
                      8,
                    ),
                    child: Column(
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: _push.enabled,
                          builder: (context, enabled, _) {
                            if (!_push.configured || enabled) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _NotificationActivationCard(
                                busy: _pushBusy,
                                error: _push.lastRegistrationError.value,
                                onEnable: _enableNotifications,
                              ),
                            );
                          },
                        ),
                        TextField(
                          controller: _search,
                          enabled: !_searching,
                          textInputAction: TextInputAction.search,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText:
                                '${context.tr('unique_username')} / ${context.tr('friend_id')}',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: IconButton(
                              tooltip: context.tr('try_again'),
                              onPressed: _searching ? null : _findPlayers,
                              icon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                            ),
                          ),
                          onSubmitted: (_) => _findPlayers(),
                        ),
                        if (_results.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final player in _results.take(5))
                            _PlayerCard(
                              player: player,
                              busy: _busyId == 'friend-${player.publicId}',
                              primaryLabel: context.tr('add_friend'),
                              onPrimary: () => _sendFriendRequest(player),
                            ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: ListTile(
                              leading: const DuelAssetIcon(
                                DuelAsset.cloud,
                                size: 24,
                              ),
                              title: Text(_error!),
                              trailing: IconButton(
                                tooltip: context.tr('dismiss'),
                                onPressed: () => setState(() => _error = null),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _requestsView(),
                          _playersView(_friends),
                          _challengesView(),
                          _playersView(_opponents),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestsView() {
    if (_requests.isEmpty) {
      return _Empty(message: context.tr('friend_requests_empty'));
    }
    return _scroll([
      for (final player in _requests)
        _PlayerCard(
          player: player,
          busy: _busyId == 'request-${player.publicId}',
          primaryLabel: context.tr('accept'),
          secondaryLabel: context.tr('decline'),
          onPrimary: () => _respondRequest(player, true),
          onSecondary: () => _respondRequest(player, false),
        ),
    ]);
  }

  Widget _playersView(List<SocialPlayer> players) {
    if (players.isEmpty) {
      return _Empty(message: context.tr('try_again_when_connected'));
    }
    return _scroll([
      for (final player in players)
        _PlayerCard(
          player: player,
          busy: _busyId == 'challenge-${player.publicId}',
          primaryLabel: context.tr('challenge'),
          onPrimary: () => _challenge(player),
        ),
    ]);
  }

  Widget _challengesView() {
    if (_incoming.isEmpty) {
      return _Empty(message: context.tr('challenge_timed_out'));
    }
    return _scroll([
      for (final challenge in _incoming)
        _ChallengeCard(
          challenge: challenge,
          onTap: () => _openChallenge(challenge),
        ),
    ]);
  }

  Widget _scroll(List<Widget> children) {
    final metrics = ResponsiveMetrics.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            metrics.pagePadding,
            8,
            metrics.pagePadding,
            32,
          ),
          children: children,
        ),
      ),
    );
  }
}

class _NotificationActivationCard extends StatelessWidget {
  const _NotificationActivationCard({
    required this.busy,
    required this.error,
    required this.onEnable,
  });

  final bool busy;
  final String? error;
  final Future<bool> Function() onEnable;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF3AA9FF);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101B20).withValues(alpha: .97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .38)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final message = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('online_challenge_notifications'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      error ??
                          context.tr('online_challenge_notifications_subtitle'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .64),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: busy ? null : () => onEnable(),
            icon: busy
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_rounded),
            label: Text(context.tr('continue_action')),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [message, const SizedBox(height: 10), button],
            );
          }
          return Row(
            children: [
              Expanded(child: message),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.busy,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final SocialPlayer player;
  final bool busy;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final metrics = ResponsiveMetrics.of(context);
    return Card(
      color: const Color(0xFF101B20).withValues(alpha: .95),
      child: Padding(
        padding: EdgeInsets.all(metrics.isTiny ? 10 : 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 430 || metrics.hasLargeText;
            final identity = Row(
              children: [
                PlayerAvatar(
                  displayName: player.displayName,
                  avatarKey: 'player-${player.publicId}',
                  radius: compact ? 22 : 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        context.tr('player_rating_summary', <Object>[
                          player.username,
                          player.rating,
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final actions = <Widget>[
              if (secondaryLabel != null)
                TextButton(
                  onPressed: busy ? null : onSecondary,
                  child: Text(secondaryLabel!),
                ),
              FilledButton.tonal(
                onPressed: busy ? null : onPrimary,
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(primaryLabel, textAlign: TextAlign.center),
              ),
            ];
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 12),
                  AdaptiveActionGroup(children: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 12),
                AdaptiveActionGroup(stretchOnCompact: false, children: actions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge, required this.onTap});

  final SocialChallenge challenge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final difficulty = SudokuDifficulty.values.firstWhere(
      (value) => value.name == challenge.difficulty,
      orElse: () => SudokuDifficulty.easy,
    );
    final accent = _accent(difficulty);
    return Card(
      color: const Color(0xFF101B20).withValues(alpha: .96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: .3)),
      ),
      child: ListTile(
        minTileHeight: 82,
        leading: PlayerAvatar(
          displayName: challenge.challenger.displayName,
          avatarKey: 'social-${challenge.challenger.publicId}',
          radius: 25,
        ),
        title: Text(
          challenge.challenger.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          '${context.strings.difficultyLabel(difficulty)} · ${context.tr('rating_value', <Object>[challenge.challenger.rating])}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withValues(alpha: .6)),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: accent),
        onTap: onTap,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DuelAssetIcon(DuelAsset.people, size: 54),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: .72)),
            ),
          ],
        ),
      ),
    );
  }
}

Color _accent(SudokuDifficulty difficulty) {
  return switch (difficulty) {
    SudokuDifficulty.beginner => const Color(0xFF29D398),
    SudokuDifficulty.easy => const Color(0xFF3AA9FF),
    SudokuDifficulty.medium => const Color(0xFFFFC94D),
    SudokuDifficulty.hard => const Color(0xFFFF8A3D),
    SudokuDifficulty.expert => const Color(0xFFFF5C7A),
  };
}
