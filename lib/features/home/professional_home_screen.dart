import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/user_safe_error.dart';
import '../../data/local_progress_store.dart';
import '../../data/ux_game_session_store.dart';
import '../../domain/classic16_puzzle_factory.dart';
import '../../domain/sudoku.dart';
import '../../domain/sudoku_variant.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/player_profile_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/player_avatar.dart';
import '../career/career_hub_screen.dart';
import '../duel/matchmaking_screen.dart';
import '../economy/coin_store_screen.dart';
import '../game/enhanced_game_screen.dart';
import '../settings/ux_settings_screen.dart';
import '../social/profile_hub_screen.dart';
import '../social/social_hub_screen.dart';
import '../social/ux_challenge_invitation_screen.dart';

class ProfessionalHomeScreen extends StatefulWidget {
  const ProfessionalHomeScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<ProfessionalHomeScreen> createState() =>
      _ProfessionalHomeScreenState();
}

class _ProfessionalHomeScreenState extends State<ProfessionalHomeScreen> {
  final EconomyService _economy = EconomyService.instance;
  final UxGameSessionStore _sessions = UxGameSessionStore.instance;
  final PushNotificationService _push = PushNotificationService.instance;

  PlayerProfilePreferences? _profile;
  UxGameSession? _activeSession;
  int _socialBadge = 0;
  bool _identityBusy = false;
  bool _routingPush = false;
  bool _openingGame = false;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_refresh);
    _sessions.activeSession.addListener(_sessionChanged);
    _push.openedChallengeId.addListener(_schedulePushRouting);
    _push.openedRematchId.addListener(_schedulePushRouting);
    unawaited(_economy.initialize());
    unawaited(_sessions.initialize());
    unawaited(_loadProfile());
    unawaited(_loadSocialBadge());
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePushRouting());
  }

  @override
  void dispose() {
    _economy.removeListener(_refresh);
    _sessions.activeSession.removeListener(_sessionChanged);
    _push.openedChallengeId.removeListener(_schedulePushRouting);
    _push.openedRematchId.removeListener(_schedulePushRouting);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    if (mounted) setState(() => _activeSession = _sessions.activeSession.value);
  }

  Future<void> _loadProfile() async {
    try {
      final value = await PlayerProfileService.instance.load();
      if (mounted) setState(() => _profile = value);
    } catch (_) {
      // Offline play remains available without a remote profile.
    }
  }

  Future<void> _loadSocialBadge() async {
    if (!SocialApiClient.instance.configured) return;
    try {
      await FirebaseSessionService.ensureAnonymousSession();
      final values = await Future.wait<Object>([
        PlayerProfileService.instance.load(),
        SocialApiClient.instance.loadIncomingFriendRequests(),
        SocialApiClient.instance.loadPendingChallenges(),
      ]);
      final profile = values[0] as PlayerProfilePreferences;
      final requests = values[1] as List<SocialPlayer>;
      final challenges = values[2] as List<SocialChallenge>;
      final incoming = challenges.where(
        (challenge) =>
            challenge.status == 'pending' &&
            challenge.recipient.publicId == profile.publicId,
      );
      if (mounted) {
        setState(() {
          _profile = profile;
          _socialBadge = requests.length + incoming.length;
        });
      }
    } catch (_) {
      // Badge loading is optional.
    }
  }

  Future<void> _refreshAfterRoute() async {
    await Future.wait<void>([
      _economy.refresh(showLoading: false),
      _sessions.latest().then((_) {}),
      _loadProfile(),
      _loadSocialBadge(),
    ]);
  }

  void _schedulePushRouting() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_routePendingPush());
    });
  }

  Future<void> _routePendingPush() async {
    if (!mounted || _routingPush || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    final challengeId = _push.openedChallengeId.value;
    final rematchId = _push.openedRematchId.value;
    if ((challengeId == null || challengeId.isEmpty) &&
        (rematchId == null || rematchId.isEmpty)) {
      return;
    }
    setState(() => _routingPush = true);
    try {
      if (!await _ensureOnlineIdentity() || !mounted) return;
      if (challengeId != null && challengeId.isNotEmpty) {
        _push.openedChallengeId.value = null;
        await _open(UxChallengeInvitationScreen(challengeId: challengeId));
      } else {
        _push.openedRematchId.value = null;
        await _open(const SocialHubScreen());
      }
    } finally {
      if (mounted) setState(() => _routingPush = false);
    }
  }

  Future<bool> _ensureOnlineIdentity() async {
    if (_identityBusy) return false;
    if (!SocialApiClient.instance.configured) {
      await GameModal.show(
        context,
        title: context.tr('online_account_unavailable'),
        message: context.tr('try_again_when_connected'),
        tone: GameModalTone.offline,
        primaryLabel: context.tr('try_again'),
      );
      return false;
    }
    setState(() => _identityBusy = true);
    try {
      await FirebaseSessionService.ensureAnonymousSession();
      await SocialApiClient.instance.ensureProfile();
      var profile = await PlayerProfileService.instance.load();
      if (!mounted) return false;
      setState(() => _profile = profile);
      if (!profile.profileConfirmed) {
        await _open(const ProfileHubScreen());
        profile = await PlayerProfileService.instance.load();
        if (!mounted) return false;
        setState(() => _profile = profile);
      }
      return profile.profileConfirmed;
    } on PlayerProfileException catch (error) {
      if (mounted) {
        await _showOnlineError(UserSafeError.message(context, error));
      }
      return false;
    } on SocialApiException catch (error) {
      if (mounted) {
        await _showOnlineError(UserSafeError.message(context, error));
      }
      return false;
    } catch (_) {
      if (mounted) {
        await _showOnlineError(context.tr('try_again_when_connected'));
      }
      return false;
    } finally {
      if (mounted) setState(() => _identityBusy = false);
    }
  }

  Future<void> _showOnlineError(String message) => GameModal.error(
    context,
    title: context.tr('online_account_unavailable'),
    message: message,
    retryLabel: context.tr('try_again'),
    cancelLabel: context.tr('cancel'),
  );

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (mounted) await _refreshAfterRoute();
  }

  Future<void> _openOnline() async {
    if (!await _ensureOnlineIdentity() || !mounted) return;
    await _open(const MatchmakingScreen());
  }

  Future<void> _openSocial() async {
    if (!await _ensureOnlineIdentity() || !mounted) return;
    await _open(const SocialHubScreen());
  }

  Future<void> _openProfile() async {
    if (!await _ensureOnlineIdentity() || !mounted) return;
    await _open(const ProfileHubScreen());
  }

  Future<void> _showQuickPlay() async {
    final selection = await showDialog<
        ({SudokuVariant variant, SudokuDifficulty difficulty})>(
      context: context,
      builder: (_) => const _QuickPlayDialog(),
    );
    if (selection == null || !mounted) return;
    await _startPractice(selection.variant, selection.difficulty);
  }

  Future<void> _startPractice(
    SudokuVariant variant,
    SudokuDifficulty difficulty,
  ) async {
    if (_openingGame) return;
    setState(() => _openingGame = true);
    try {
      final puzzle = variant.id == SudokuVariantId.classic16
          ? Classic16PuzzleFactory.generate(difficulty: difficulty)
          : SudokuEngine.generate(difficulty: difficulty, size: 9);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EnhancedGameScreen(
            puzzle: puzzle,
            store: widget.store,
            showNextAction: false,
            onCompleted:
                ({required seconds, required mistakes, required hints}) =>
                    widget.store.recordResult(
                      puzzleId: puzzle.id,
                      seconds: seconds,
                      mistakes: mistakes,
                      hints: hints,
                      variant: variant,
                    ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingGame = false);
        await _refreshAfterRoute();
      }
    }
  }

  Future<void> _resume() async {
    final session = _activeSession;
    if (session == null || _openingGame) return;
    setState(() => _openingGame = true);
    try {
      final variant = session.puzzle.variant;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EnhancedGameScreen(
            puzzle: session.puzzle,
            store: widget.store,
            showNextAction: false,
            onCompleted:
                ({required seconds, required mistakes, required hints}) =>
                    widget.store.recordResult(
                      puzzleId: session.puzzle.id,
                      seconds: seconds,
                      mistakes: mistakes,
                      hints: hints,
                      variant: variant,
                    ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingGame = false);
        await _refreshAfterRoute();
      }
    }
  }

  Future<void> _claimReward() async {
    final wallet = _economy.wallet;
    bool claimed = false;
    if (wallet?.dailyLoginAvailable == true) {
      claimed = await _economy.claimDailyLogin();
    } else if (wallet?.dailyAdAvailable == true && !_economy.noAds) {
      claimed = await _economy.claimDailyRewardedAd();
    }
    if (!mounted) return;
    if (claimed) {
      await GameModal.success(
        context,
        title: context.tr('home_daily_reward_title'),
        message: context.tr('coin_added_wallet', <Object>[
          wallet?.dailyLoginAvailable == true
              ? wallet?.dailyLoginAmount ?? 50
              : wallet?.dailyAdAmount ?? 50,
        ]),
        actionLabel: context.tr('continue_action'),
      );
    } else if (_economy.error != null) {
      await GameModal.error(
        context,
        title: context.tr('home_daily_reward_title'),
        message: _economy.error!,
        retryLabel: context.tr('retry'),
        cancelLabel: context.tr('cancel'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rewardReady =
        _economy.wallet?.dailyLoginAvailable == true ||
        (_economy.wallet?.dailyAdAvailable == true && !_economy.noAds);
    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              final wide = constraints.maxWidth >= 760;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      compact ? 6 : 10,
                      14,
                      compact ? 8 : 14,
                    ),
                    child: Column(
                      children: [
                        _HomeHeader(
                          profile: _profile,
                          balance: _economy.balance,
                          badge: _socialBadge,
                          rewardReady: rewardReady,
                          identityBusy: _identityBusy,
                          onProfile: _openProfile,
                          onSocial: _openSocial,
                          onReward: _claimReward,
                          onSettings: () => _open(
                            UxSettingsScreen(store: widget.store),
                          ),
                        ),
                        SizedBox(height: compact ? 6 : 10),
                        Text(
                          context.tr('app_name').toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 25 : 34,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            shadows: const [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 18,
                                offset: Offset(0, 7),
                              ),
                            ],
                          ),
                        ),
                        if (_activeSession != null) ...[
                          SizedBox(height: compact ? 6 : 10),
                          _ResumeStrip(
                            session: _activeSession!,
                            busy: _openingGame,
                            onTap: _resume,
                          ),
                        ],
                        SizedBox(height: compact ? 7 : 12),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, gridConstraints) {
                              const itemCount = 6;
                              final columns = wide ? 3 : 2;
                              final rows = (itemCount / columns).ceil();
                              final gap = compact ? 7.0 : 10.0;
                              final extent =
                                  (gridConstraints.maxHeight - gap * (rows - 1)) /
                                  rows;
                              final items = <_HomeModeData>[
                                _HomeModeData(
                                  asset: DuelAsset.quickPlayPro,
                                  title: context.tr('play'),
                                  subtitle: '9×9 · 16×16',
                                  accent: const Color(0xFFFFC73D),
                                  onTap: _showQuickPlay,
                                  primary: true,
                                ),
                                _HomeModeData(
                                  asset: DuelAsset.onlineDuelPro,
                                  title: context.tr('online_duel'),
                                  subtitle: context.tr('online_duel_subtitle'),
                                  accent: const Color(0xFFFF525E),
                                  onTap: _identityBusy ? null : _openOnline,
                                  primary: true,
                                ),
                                _HomeModeData(
                                  asset: DuelAsset.careerPro,
                                  title: context.tr('career'),
                                  subtitle: context.tr('completed_levels', <Object>[
                                    widget.store.completedCareerLevelCount,
                                  ]),
                                  accent: const Color(0xFFFFC73D),
                                  onTap: () => _open(
                                    CareerHubScreen(store: widget.store),
                                  ),
                                ),
                                _HomeModeData(
                                  asset: DuelAsset.friendsPro,
                                  title: context.tr('friends_challenges'),
                                  subtitle: _socialBadge > 0
                                      ? '$_socialBadge'
                                      : context.tr('friend_requests'),
                                  accent: const Color(0xFF35D2FF),
                                  onTap: _identityBusy ? null : _openSocial,
                                ),
                                _HomeModeData(
                                  asset: DuelAsset.storePro,
                                  title: context.tr('coin_store'),
                                  subtitle: NumberFormat.compact().format(
                                    _economy.balance,
                                  ),
                                  accent: const Color(0xFF29D398),
                                  onTap: () => _open(const CoinStoreScreen()),
                                ),
                                _HomeModeData(
                                  asset: DuelAsset.profilePro,
                                  title: context.tr('profile'),
                                  subtitle: context.tr('shown_to_other_players'),
                                  accent: const Color(0xFF7A5CFF),
                                  onTap: _identityBusy ? null : _openProfile,
                                ),
                              ];
                              return GridView.builder(
                                padding: EdgeInsets.zero,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: items.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: gap,
                                      mainAxisSpacing: gap,
                                      mainAxisExtent: extent,
                                    ),
                                itemBuilder: (context, index) => _HomeModeTile(
                                  data: items[index],
                                  compact: compact,
                                ),
                              );
                            },
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
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.profile,
    required this.balance,
    required this.badge,
    required this.rewardReady,
    required this.identityBusy,
    required this.onProfile,
    required this.onSocial,
    required this.onReward,
    required this.onSettings,
  });

  final PlayerProfilePreferences? profile;
  final int balance;
  final int badge;
  final bool rewardReady;
  final bool identityBusy;
  final VoidCallback onProfile;
  final VoidCallback onSocial;
  final VoidCallback onReward;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? 'Sudoku Player';
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: identityBusy ? null : onProfile,
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: [
                  PlayerAvatar(
                    displayName: name,
                    avatarKey: 'professional-home-$name',
                    radius: 20,
                    semanticLabel: context.tr(
                      'player_avatar_semantics',
                      <Object>[name],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (rewardReady)
            _HeaderButton(
              tooltip: context.tr('home_daily_reward_title'),
              onTap: onReward,
              child: const Icon(
                Icons.redeem_rounded,
                color: Color(0xFFFFC73D),
              ),
            ),
          const SizedBox(width: 5),
          _HeaderButton(
            tooltip: context.tr('friends_challenges'),
            onTap: identityBusy ? null : onSocial,
            child: Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: const Icon(Icons.people_alt_rounded),
            ),
          ),
          const SizedBox(width: 5),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728).withValues(alpha: .9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFFFC73D).withValues(alpha: .34),
              ),
            ),
            child: Row(
              children: [
                const DuelAssetIcon(DuelAsset.coin, size: 18),
                const SizedBox(width: 5),
                Text(
                  NumberFormat.compact().format(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          _HeaderButton(
            tooltip: context.tr('settings'),
            onTap: onSettings,
            child: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    style: IconButton.styleFrom(
      fixedSize: const Size(44, 44),
      backgroundColor: const Color(0xFF0A1728).withValues(alpha: .9),
      side: BorderSide(color: Colors.white.withValues(alpha: .13)),
    ),
    icon: child,
  );
}

class _ResumeStrip extends StatelessWidget {
  const _ResumeStrip({
    required this.session,
    required this.busy,
    required this.onTap,
  });

  final UxGameSession session;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final variant = session.puzzle.variant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF12352A).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF29D398).withValues(alpha: .55),
            ),
          ),
          child: Row(
            children: [
              busy
                  ? const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Color(0xFF29D398),
                      size: 34,
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('continue_action'),
                      style: const TextStyle(
                        color: Color(0xFF29D398),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${variant.label} · ${context.strings.difficultyLabel(session.puzzle.difficulty)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeModeData {
  const _HomeModeData({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.primary = false,
  });

  final String asset;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;
  final bool primary;
}

class _HomeModeTile extends StatelessWidget {
  const _HomeModeTile({required this.data, required this.compact});

  final _HomeModeData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: data.onTap != null,
      label: '${data.title}. ${data.subtitle}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(data.primary ? 22 : 18),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728).withValues(alpha: .93),
              borderRadius: BorderRadius.circular(data.primary ? 22 : 18),
              border: Border.all(
                color: data.accent.withValues(alpha: data.primary ? .7 : .35),
                width: data.primary ? 1.8 : 1,
              ),
              boxShadow: data.primary
                  ? [
                      BoxShadow(
                        color: data.accent.withValues(alpha: .12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 7 : 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: DuelAssetIcon(
                      data.asset,
                      size: compact ? 78 : 108,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 14 : data.primary ? 18 : 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    data.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: data.accent.withValues(alpha: .82),
                      fontSize: compact ? 10 : 12,
                      fontWeight: FontWeight.w800,
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
}

class _QuickPlayDialog extends StatefulWidget {
  const _QuickPlayDialog();

  @override
  State<_QuickPlayDialog> createState() => _QuickPlayDialogState();
}

class _QuickPlayDialogState extends State<_QuickPlayDialog> {
  SudokuVariant _variant = SudokuVariant.classic9;
  SudokuDifficulty _difficulty = SudokuDifficulty.easy;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF081522),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFFFFC73D).withValues(alpha: .5),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, 16),
              ),
            ],
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
                        context.tr('play'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final variant in SudokuVariant.values) ...[
                      Expanded(
                        child: _DialogVariantCard(
                          variant: variant,
                          selected: _variant.id == variant.id,
                          onTap: () => setState(() => _variant = variant),
                        ),
                      ),
                      if (variant != SudokuVariant.values.last)
                        const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
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
                        label: Text(
                          context.strings.difficultyLabel(difficulty),
                        ),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop((
                      variant: _variant,
                      difficulty: _difficulty,
                    )),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: const Color(0xFF29D398),
                      foregroundColor: const Color(0xFF07111E),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
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
}

class _DialogVariantCard extends StatelessWidget {
  const _DialogVariantCard({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final SudokuVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final is16 = variant.id == SudokuVariantId.classic16;
    final accent = is16 ? const Color(0xFF35D2FF) : const Color(0xFFFFC73D);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 148,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: .14)
                : const Color(0xFF0A1728),
            borderRadius: BorderRadius.circular(18),
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
                size: 96,
              ),
              Text(
                variant.label,
                style: TextStyle(
                  color: selected ? accent : Colors.white,
                  fontSize: 18,
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
