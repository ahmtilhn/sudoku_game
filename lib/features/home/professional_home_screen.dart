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
    if (!mounted ||
        _routingPush ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
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
    final primaryItems = <_HomeModeData>[
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
    ];
    final secondaryItems = <_HomeModeData>[
      _HomeModeData(
        asset: DuelAsset.careerPro,
        title: context.tr('career'),
        subtitle: context.tr('completed_levels', <Object>[
          widget.store.completedCareerLevelCount,
        ]),
        accent: const Color(0xFFFFC73D),
        onTap: () => _open(CareerHubScreen(store: widget.store)),
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
        subtitle: NumberFormat.compact().format(_economy.balance),
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        SizedBox(height: compact ? 4 : 7),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            context.tr('app_name').toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 22 : 27,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .9,
                            ),
                          ),
                        ),
                        if (_activeSession != null) ...[
                          SizedBox(height: compact ? 6 : 8),
                          _ResumeStrip(
                            session: _activeSession!,
                            busy: _openingGame,
                            onTap: _resume,
                          ),
                        ],
                        SizedBox(height: compact ? 8 : 12),
                        _PrimaryModes(
                          items: primaryItems,
                          compact: compact,
                          wide: wide,
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        _SecondaryModes(
                          items: secondaryItems,
                          compact: compact,
                          wide: wide,
                        ),
                        const Spacer(),
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
      height: 44,
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
                    radius: 18,
                    semanticLabel: context.tr(
                      'player_avatar_semantics',
                      <Object>[name],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
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
                size: 20,
              ),
            ),
          const SizedBox(width: 4),
          _HeaderButton(
            tooltip: context.tr('friends_challenges'),
            onTap: identityBusy ? null : onSocial,
            child: Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: const Icon(Icons.people_alt_rounded, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728).withValues(alpha: .9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFFFC73D).withValues(alpha: .34),
              ),
            ),
            child: Row(
              children: [
                const DuelAssetIcon(DuelAsset.coin, size: 16),
                const SizedBox(width: 4),
                Text(
                  NumberFormat.compact().format(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          _HeaderButton(
            tooltip: context.tr('settings'),
            onTap: onSettings,
            child: const Icon(Icons.settings_rounded, size: 20),
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
      fixedSize: const Size(38, 38),
      padding: EdgeInsets.zero,
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
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF12352A).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF29D398).withValues(alpha: .55),
            ),
          ),
          child: Row(
            children: [
              busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Color(0xFF29D398),
                      size: 28,
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${context.tr('continue_action')}  ',
                        style: const TextStyle(
                          color: Color(0xFF29D398),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text:
                            '${variant.label} · ${context.strings.difficultyLabel(session.puzzle.difficulty)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white70,
                size: 20,
              ),
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

class _PrimaryModes extends StatelessWidget {
  const _PrimaryModes({
    required this.items,
    required this.compact,
    required this.wide,
  });

  final List<_HomeModeData> items;
  final bool compact;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (wide) {
      return SizedBox(
        height: compact ? 104 : 118,
        child: Row(
          children: [
            Expanded(child: _HomeModeTile(data: items[0], compact: compact)),
            const SizedBox(width: 10),
            Expanded(child: _HomeModeTile(data: items[1], compact: compact)),
          ],
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: compact ? 86 : 94,
          child: _HomeModeTile(data: items[0], compact: compact),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: compact ? 86 : 94,
          child: _HomeModeTile(data: items[1], compact: compact),
        ),
      ],
    );
  }
}

class _SecondaryModes extends StatelessWidget {
  const _SecondaryModes({
    required this.items,
    required this.compact,
    required this.wide,
  });

  final List<_HomeModeData> items;
  final bool compact;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final columns = wide ? 4 : 2;
    final itemHeight = compact ? 72.0 : 82.0;
    final rows = (items.length / columns).ceil();
    return SizedBox(
      height: rows * itemHeight + (rows - 1) * 8,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: itemHeight,
        ),
        itemBuilder: (context, index) => _HomeModeTile(
          data: items[index],
          compact: compact,
        ),
      ),
    );
  }
}

class _HomeModeTile extends StatelessWidget {
  const _HomeModeTile({required this.data, required this.compact});

  final _HomeModeData data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = data.primary ? 18.0 : 15.0;
    final iconSize = data.primary
        ? compact
              ? 54.0
              : 66.0
        : compact
        ? 38.0
        : 44.0;
    return Semantics(
      button: true,
      enabled: data.onTap != null,
      label: '${data.title}. ${data.subtitle}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: data.primary ? 12 : 10,
              vertical: data.primary ? 9 : 7,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728).withValues(alpha: .93),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: data.accent.withValues(alpha: data.primary ? .62 : .3),
                width: data.primary ? 1.5 : 1,
              ),
              boxShadow: data.primary
                  ? [
                      BoxShadow(
                        color: data.accent.withValues(alpha: .09),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: iconSize,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: DuelAssetIcon(data.asset, size: iconSize),
                  ),
                ),
                SizedBox(width: data.primary ? 10 : 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: data.primary
                              ? compact
                                    ? 15
                                    : 17
                              : compact
                              ? 12
                              : 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: data.accent.withValues(alpha: .82),
                          fontSize: data.primary ? 11 : 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: .48),
                  size: data.primary ? 24 : 20,
                ),
              ],
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF081522),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFFC73D).withValues(alpha: .45),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 26,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                          fontSize: 21,
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
                const SizedBox(height: 6),
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
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
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
                        visualDensity: VisualDensity.compact,
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop((
                      variant: _variant,
                      difficulty: _difficulty,
                    )),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
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
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 9),
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
          child: Row(
            children: [
              DuelAssetIcon(
                is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                size: 54,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accent : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      is16 ? '1–16' : '1–9',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
