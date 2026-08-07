import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../domain/sudoku_variant.dart';
import '../../localization/app_strings.dart';
import '../../services/player_profile_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/player_avatar.dart';
import 'challenge_waiting_screen.dart';
import 'ux_challenge_invitation_screen.dart';

enum _SocialTab { requests, friends, challenges, recent }

class SocialHubScreen extends StatefulWidget {
  const SocialHubScreen({super.key});

  @override
  State<SocialHubScreen> createState() => _SocialHubScreenState();
}

class _SocialHubScreenState extends State<SocialHubScreen> {
  final SocialApiClient _social = SocialApiClient.instance;
  final PushNotificationService _push = PushNotificationService.instance;
  final TextEditingController _search = TextEditingController();

  PlayerProfilePreferences? _me;
  List<SocialPlayer> _friends = const <SocialPlayer>[];
  List<SocialPlayer> _requests = const <SocialPlayer>[];
  List<SocialPlayer> _opponents = const <SocialPlayer>[];
  List<SocialChallenge> _challenges = const <SocialChallenge>[];
  List<SocialPlayer> _results = const <SocialPlayer>[];
  _SocialTab _tab = _SocialTab.friends;
  bool _loading = true;
  bool _searching = false;
  bool _pushBusy = false;
  bool _showingError = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_prepareNotifications());
  }

  @override
  void dispose() {
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

  Future<void> _enableNotifications() async {
    if (_pushBusy) return;
    setState(() => _pushBusy = true);
    try {
      final enabled = await _push.requestPermissionAndRegister();
      if (!mounted) return;
      if (enabled) {
        await GameModal.success(
          context,
          title: context.tr('challenge_notifications'),
          message: context.tr('challenge_notification_enabled'),
          actionLabel: context.tr('continue_action'),
        );
      } else {
        await GameModal.show(
          context,
          title: context.tr('challenge_notifications'),
          message:
              _push.lastRegistrationError.value ??
              context.tr('challenge_notification_permission_denied'),
          tone: GameModalTone.warning,
          primaryLabel: context.tr('try_again'),
        );
      }
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
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
      if (mounted) await _presentError(error, retry: _load);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _presentError(
    Object error, {
    Future<void> Function()? retry,
  }) async {
    if (_showingError || !mounted) return;
    _showingError = true;
    final shouldRetry = await GameModal.error(
      context,
      title: context.tr('friends_challenges'),
      message: UserSafeError.message(context, error),
      retryLabel: retry == null ? context.tr('continue_action') : context.tr('retry'),
      cancelLabel: context.tr('cancel'),
    );
    _showingError = false;
    if (shouldRetry == true && retry != null && mounted) {
      unawaited(retry());
    }
  }

  Future<bool> _perform(String id, Future<void> Function() action) async {
    if (_busyId != null) return false;
    setState(() => _busyId = id);
    try {
      await action();
      await _load();
      return true;
    } catch (error) {
      if (mounted) await _presentError(error);
      return false;
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _findPlayers() async {
    final query = _search.text.trim();
    if (query.length < 3 || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final values = await _social.searchPlayers(query);
      if (mounted) setState(() => _results = values);
    } catch (error) {
      if (mounted) await _presentError(error, retry: _findPlayers);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendFriendRequest(SocialPlayer player) async {
    final success = await _perform('friend-${player.publicId}', () async {
      await _social.sendFriendRequest(player.publicId);
    });
    if (!success || !mounted) return;
    await GameModal.success(
      context,
      title: context.tr('add_friend'),
      message: context.tr('friend_request_sent'),
      actionLabel: context.tr('continue_action'),
    );
  }

  Future<void> _respondRequest(SocialPlayer player, bool accept) async {
    final success = await _perform('request-${player.publicId}', () async {
      await _social.respondToFriendRequest(
        requesterPublicId: player.publicId,
        accept: accept,
      );
    });
    if (!success || !accept || !mounted) return;
    await GameModal.success(
      context,
      title: context.tr('friends'),
      message: context.tr(
        'friend_request_accepted',
        <Object>[player.displayName],
      ),
      actionLabel: context.tr('continue_action'),
    );
  }

  Future<void> _challenge(SocialPlayer player) async {
    final selection = await showDialog<
        ({SudokuVariant variant, SudokuDifficulty difficulty})>(
      context: context,
      builder: (_) => const _ChallengeSetupDialog(),
    );
    if (selection == null || _busyId != null || !mounted) return;

    if (!_push.enabled.value && !_push.userDisabled.value) {
      await _enableNotifications();
      if (!mounted) return;
    }

    setState(() => _busyId = 'challenge-${player.publicId}');
    try {
      final challenge = await _social.createChallenge(
        recipientPublicId: player.publicId,
        difficulty: selection.difficulty.name,
        variant: selection.variant,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChallengeWaitingScreen(challenge: challenge),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) await _presentError(error);
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

  @override
  Widget build(BuildContext context) {
    final searchingResults = _results.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
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
                        _searchBar(),
                        SizedBox(height: compact ? 7 : 10),
                        if (searchingResults)
                          _searchModeHeader()
                        else
                          _tabBar(compact),
                        SizedBox(height: compact ? 7 : 10),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : searchingResults
                              ? _playersList(
                                  _results,
                                  mode: _PlayerMode.search,
                                )
                              : _selectedView(),
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
    final notificationsNeedAction =
        _push.configured && !_push.enabled.value && !_push.userDisabled.value;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('friends_challenges'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: context.tr('challenge_notifications'),
            onPressed: _pushBusy ? null : _enableNotifications,
            icon: _pushBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    isLabelVisible: notificationsNeedAction,
                    child: Icon(
                      _push.enabled.value
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: context.tr('refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return SizedBox(
      height: 54,
      child: TextField(
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_rounded),
          ),
          filled: true,
          fillColor: const Color(0xFF0A1728).withValues(alpha: .94),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (_) => _findPlayers(),
      ),
    );
  }

  Widget _searchModeHeader() {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          const Icon(Icons.manage_search_rounded, color: Color(0xFF35D2FF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.tr('search')} · ${_results.length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              _search.clear();
              setState(() => _results = const <SocialPlayer>[]);
            },
            icon: const Icon(Icons.close_rounded),
            label: Text(context.tr('dismiss')),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(bool compact) {
    final tabs = <({
      _SocialTab tab,
      IconData icon,
      String label,
      int count,
    })>[
      (
        tab: _SocialTab.requests,
        icon: Icons.person_add_alt_1_rounded,
        label: context.tr('friend_requests'),
        count: _requests.length,
      ),
      (
        tab: _SocialTab.friends,
        icon: Icons.people_alt_rounded,
        label: context.tr('friends'),
        count: _friends.length,
      ),
      (
        tab: _SocialTab.challenges,
        icon: Icons.sports_kabaddi_rounded,
        label: context.tr('challenge'),
        count: _incoming.length,
      ),
      (
        tab: _SocialTab.recent,
        icon: Icons.history_rounded,
        label: context.tr('opponent'),
        count: _opponents.length,
      ),
    ];
    return SizedBox(
      height: compact ? 58 : 66,
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++) ...[
            Expanded(child: _tabButton(tabs[index], compact)),
            if (index != tabs.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _tabButton(
    ({_SocialTab tab, IconData icon, String label, int count}) value,
    bool compact,
  ) {
    final selected = _tab == value.tab;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _tab = value.tab),
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF29D398).withValues(alpha: .18)
                : const Color(0xFF0A1728).withValues(alpha: .9),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? const Color(0xFF29D398)
                  : Colors.white.withValues(alpha: .1),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: value.count > 0,
                label: Text('${value.count}'),
                child: Icon(
                  value.icon,
                  color: selected ? const Color(0xFF29D398) : Colors.white70,
                  size: compact ? 20 : 23,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedView() {
    return switch (_tab) {
      _SocialTab.requests => _requestsList(),
      _SocialTab.friends => _playersList(_friends, mode: _PlayerMode.friend),
      _SocialTab.challenges => _challengeList(),
      _SocialTab.recent => _playersList(_opponents, mode: _PlayerMode.recent),
    };
  }

  Widget _requestsList() {
    if (_requests.isEmpty) return _empty(context.tr('friend_requests_empty'));
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final player = _requests[index];
        return _PlayerTile(
          player: player,
          busy: _busyId == 'request-${player.publicId}',
          primaryLabel: context.tr('accept'),
          secondaryLabel: context.tr('decline'),
          onPrimary: () => _respondRequest(player, true),
          onSecondary: () => _respondRequest(player, false),
        );
      },
    );
  }

  Widget _playersList(
    List<SocialPlayer> players, {
    required _PlayerMode mode,
  }) {
    if (players.isEmpty) {
      return _empty(
        mode == _PlayerMode.search
            ? context.tr('no_results')
            : context.tr('friends_empty'),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: players.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final player = players[index];
        final search = mode == _PlayerMode.search;
        return _PlayerTile(
          player: player,
          busy:
              _busyId ==
              (search
                  ? 'friend-${player.publicId}'
                  : 'challenge-${player.publicId}'),
          primaryLabel: search
              ? context.tr('add_friend')
              : context.tr('challenge'),
          onPrimary: search
              ? () => _sendFriendRequest(player)
              : () => _challenge(player),
        );
      },
    );
  }

  Widget _challengeList() {
    final incoming = _incoming;
    if (incoming.isEmpty) return _empty(context.tr('challenges_empty'));
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: incoming.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final challenge = incoming[index];
        return _ChallengeTile(
          challenge: challenge,
          onTap: () => _openChallenge(challenge),
        );
      },
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DuelAssetIcon(DuelAsset.friendsPro, size: 132),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PlayerMode { search, friend, recent }

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        children: [
          PlayerAvatar(
            displayName: player.displayName,
            avatarKey: 'social-${player.publicId}',
            radius: 27,
            semanticLabel: context.tr(
              'player_avatar_semantics',
              <Object>[player.displayName],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '@${player.username} · ELO ${player.rating}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            if (secondaryLabel != null && onSecondary != null)
              IconButton.filledTonal(
                tooltip: secondaryLabel,
                onPressed: onSecondary,
                icon: const Icon(Icons.close_rounded),
              ),
            if (secondaryLabel != null) const SizedBox(width: 6),
            FilledButton(
              onPressed: onPrimary,
              child: Text(primaryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChallengeTile extends StatelessWidget {
  const _ChallengeTile({required this.challenge, required this.onTap});

  final SocialChallenge challenge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final is16 = challenge.variant.id == SudokuVariantId.classic16;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 94,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1728).withValues(alpha: .94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (is16
                      ? const Color(0xFF35D2FF)
                      : const Color(0xFFFFC73D))
                  .withValues(alpha: .5),
            ),
          ),
          child: Row(
            children: [
              DuelAssetIcon(
                is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                size: 70,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.challenger.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${challenge.variant.label} · ${challenge.difficulty}',
                      style: const TextStyle(
                        color: Color(0xFF29D398),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChallengeSetupDialog extends StatefulWidget {
  const _ChallengeSetupDialog();

  @override
  State<_ChallengeSetupDialog> createState() => _ChallengeSetupDialogState();
}

class _ChallengeSetupDialogState extends State<_ChallengeSetupDialog> {
  SudokuVariant _variant = SudokuVariant.classic9;
  SudokuDifficulty _difficulty = SudokuDifficulty.easy;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF081522),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: const Color(0xFF35D2FF).withValues(alpha: .45),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('challenge'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final variant in SudokuVariant.values) ...[
                      Expanded(child: _variantChoice(variant)),
                      if (variant != SudokuVariant.values.last)
                        const SizedBox(width: 9),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final difficulty in SudokuDifficulty.values)
                      ChoiceChip(
                        selected: _difficulty == difficulty,
                        onSelected: (_) =>
                            setState(() => _difficulty = difficulty),
                        label: Text(context.strings.difficultyLabel(difficulty)),
                        showCheckmark: false,
                        selectedColor: const Color(0xFF29D398),
                        backgroundColor: const Color(0xFF132438),
                        labelStyle: TextStyle(
                          color: _difficulty == difficulty
                              ? const Color(0xFF07111E)
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop((
                      variant: _variant,
                      difficulty: _difficulty,
                    )),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      '${_variant.label} · ${context.strings.difficultyLabel(_difficulty)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _variantChoice(SudokuVariant variant) {
    final selected = _variant.id == variant.id;
    final is16 = variant.id == SudokuVariantId.classic16;
    final accent = is16 ? const Color(0xFF35D2FF) : const Color(0xFFFFC73D);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _variant = variant),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 126,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: .14)
                : const Color(0xFF0A1728),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: .12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DuelAssetIcon(
                is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                size: 82,
              ),
              Text(
                variant.label,
                style: TextStyle(
                  color: selected ? accent : Colors.white,
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
