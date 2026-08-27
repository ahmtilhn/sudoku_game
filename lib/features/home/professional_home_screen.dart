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
import '../../models/rank_identity_models.dart';
import '../../services/economy_service.dart';
import '../../services/economy_v3_api_client.dart';
import '../../services/economy_v3_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/platform_game_services.dart';
import '../../services/player_profile_service.dart';
import '../../services/rank_identity_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/player_avatar.dart';
import '../career/career_hub_screen.dart';
import '../duel/leaderboards_screen.dart';
import '../duel/matchmaking_screen.dart';
import '../economy/coin_store_screen.dart';
import '../game/enhanced_game_screen.dart';
import '../settings/ux_settings_screen.dart';
import '../social/profile_hub_screen.dart';
import '../social/social_hub_screen.dart';

class ProfessionalHomeScreen extends StatefulWidget {
  const ProfessionalHomeScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<ProfessionalHomeScreen> createState() => _ProfessionalHomeScreenState();
}

class _ProfessionalHomeScreenState extends State<ProfessionalHomeScreen> {
  final EconomyService _economy = EconomyService.instance;
  final EconomyV3Service _economyV3 = EconomyV3Service.instance;
  final UxGameSessionStore _sessions = UxGameSessionStore.instance;

  PlayerProfilePreferences? _profile;
  RankIdentityProfile? _rankProfile;
  UxGameSession? _activeSession;
  int _socialBadge = 0;
  bool _identityBusy = false;
  bool _openingGame = false;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_refresh);
    _economyV3.addListener(_refresh);
    _sessions.activeSession.addListener(_sessionChanged);
    unawaited(_economy.initialize());
    unawaited(_economyV3.initialize());
    unawaited(_sessions.initialize());
    unawaited(_loadProfile());
    unawaited(_loadRankProfile());
    unawaited(_loadSocialBadge());
  }

  @override
  void dispose() {
    _economy.removeListener(_refresh);
    _economyV3.removeListener(_refresh);
    _sessions.activeSession.removeListener(_sessionChanged);
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

  Future<void> _loadRankProfile() async {
    if (!SocialApiClient.instance.configured) return;
    try {
      final value = await RankIdentityService.instance.load();
      if (mounted) setState(() => _rankProfile = value);
    } catch (_) {
      // Ranked summary is optional on the home screen.
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
      _economyV3.refresh(),
      _sessions.latest().then((_) {}),
      _loadProfile(),
      _loadRankProfile(),
      _loadSocialBadge(),
    ]);
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
    final cached = _profile ?? PlayerProfileService.instance.current.value;
    if (cached?.profileConfirmed == true) {
      if (_profile == null && mounted) setState(() => _profile = cached);
      return true;
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
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));
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

  Future<void> _openLeaderboards() async {
    if (!await _ensureOnlineIdentity() || !mounted) return;
    await _open(const LeaderboardsScreen());
  }

  Future<void> _openRankedProgress() async {
    if (!await _ensureOnlineIdentity() || !mounted) return;
    await _open(const LeaderboardsScreen());
  }

  Future<void> _showQuickPlay() async {
    final selection =
        await showDialog<
          ({SudokuVariant variant, SudokuDifficulty difficulty})
        >(context: context, builder: (_) => const _QuickPlayDialog());
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
            allowNotes: true,
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
            allowNotes: true,
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
    await _economyV3.refresh();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .62),
      builder: (_) =>
          _DailyRewardDialog(economy: _economy, economyV3: _economyV3),
    );
    if (!mounted) return;
    await Future.wait<void>([
      _economy.refresh(showLoading: false),
      _economyV3.refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final rewardReady =
        _economyV3.state?.dailyAvailable == true ||
        (_economyV3.state?.canDoubleLastCoinReward == true && !_economy.noAds);
    final rank = _rankProfile;

    final primaryItems = <_HomeModeData>[
      _HomeModeData(
        asset: DuelAsset.homePlayScene,
        title: context.tr('play'),
        subtitle: context.tr('classic_variants_short'),
        accent: const Color(0xFFFFC73D),
        onTap: _showQuickPlay,
        primary: true,
      ),
      _HomeModeData(
        asset: DuelAsset.homeDuelScene,
        title: context.tr('online_duel'),
        subtitle: context.tr('online_duel_subtitle'),
        accent: const Color(0xFFFF525E),
        onTap: _identityBusy ? null : _openOnline,
        primary: true,
      ),
    ];

    final secondaryItems = <_HomeModeData>[
      _HomeModeData(
        asset: DuelAsset.homeCareerScene,
        title: context.tr('career'),
        subtitle: context.tr('completed_levels', <Object>[
          widget.store.completedCareerLevelCount,
        ]),
        accent: const Color(0xFFFFC73D),
        onTap: () => _open(CareerHubScreen(store: widget.store)),
      ),
      _HomeModeData(
        asset: DuelAsset.homeFriendsScene,
        title: context.tr('friends_challenges'),
        subtitle: _socialBadge > 0
            ? '$_socialBadge'
            : context.tr('friend_requests'),
        accent: const Color(0xFF35D2FF),
        onTap: _identityBusy ? null : _openSocial,
      ),
      _HomeModeData(
        asset: DuelAsset.homeStoreScene,
        title: context.tr('coin_store'),
        subtitle: NumberFormat.compact().format(_economy.balance),
        accent: const Color(0xFF29D398),
        onTap: () => _open(const CoinStoreScreen()),
      ),
      _HomeModeData(
        asset: DuelAsset.resultVictoryTrophyPro,
        title: rank?.rankName ?? 'Ranked Progress',
        subtitle: rank == null
            ? 'Rank · RP · performance'
            : rank.nextRankName == null
            ? '${rank.rankPoints} RP · Top rank'
            : '${rank.rankPoints} RP · ${rank.pointsToNext ?? 0} to ${rank.nextRankName}',
        accent: const Color(0xFF66C7FF),
        onTap: _identityBusy ? null : _openRankedProgress,
        progress: rank?.progress,
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
                          onLeaderboards: _openLeaderboards,
                          onReward: _claimReward,
                          onSettings: () =>
                              _open(UxSettingsScreen(store: widget.store)),
                        ),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _HomeLogo(compact: compact),
                                  if (_activeSession != null) ...[
                                    SizedBox(height: compact ? 4 : 6),
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
                                ],
                              ),
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
}

class _HomeLogo extends StatelessWidget {
  const _HomeLogo({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('home-logo-text'),
      height: compact ? 150 : 200,
      width: double.infinity,
      child: ClipRect(
        child: Center(
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.asset(
              'assets/images/ui/logo_text.png',
              fit: BoxFit.fitWidth,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  context.tr('app_name').toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 34 : 42,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .9,
                  ),
                ),
              ),
            ),
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
    required this.onLeaderboards,
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
  final VoidCallback onLeaderboards;
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
              child: ValueListenableBuilder<PlatformPlayer?>(
                valueListenable: PlatformGameServices.instance.localPlayer,
                builder: (context, platformPlayer, _) => Row(
                  children: [
                    PlayerAvatar(
                      displayName: name,
                      avatarKey: 'professional-home-$name',
                      localAvatarBytes: platformPlayer?.avatarBytes,
                      remoteApprovedImageUrl: platformPlayer?.avatarUrl,
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
          ),
          _HeaderButton(
            tooltip: context.tr('home_daily_reward_title'),
            onTap: rewardReady ? onReward : null,
            accent: rewardReady ? const Color(0xFFFFC73D) : null,
            child: Opacity(
              opacity: rewardReady ? 1 : .52,
              child: const DuelAssetIcon(
                DuelAsset.dailyRewardPro,
                size: 30,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _HeaderButton(
            tooltip: context.tr('leaderboards'),
            onTap: identityBusy ? null : onLeaderboards,
            accent: const Color(0xFFFFC73D),
            child: const DuelAssetIcon(
              DuelAsset.leaderboardCrownPro,
              size: 28,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 4),
          _HeaderButton(
            tooltip: context.tr('friends_challenges'),
            onTap: identityBusy ? null : onSocial,
            child: Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: const DuelAssetIcon(DuelAsset.people, size: 22),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            height: 38,
            padding: const EdgeInsets.only(left: 3, right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1728).withValues(alpha: .92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFFFC73D).withValues(alpha: .38),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DuelAssetIcon(
                  DuelAsset.coin,
                  size: 30,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 2),
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

class _DailyRewardDialog extends StatefulWidget {
  const _DailyRewardDialog({required this.economy, required this.economyV3});

  final EconomyService economy;
  final EconomyV3Service economyV3;

  @override
  State<_DailyRewardDialog> createState() => _DailyRewardDialogState();
}

class _DailyRewardDialogState extends State<_DailyRewardDialog> {
  bool _busy = false;
  String? _message;

  Future<void> _claim() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await widget.economyV3.claimDailyIfAvailable();
    await widget.economy.refresh(showLoading: false);
    if (!mounted) return;
    final reward = result?.reward;
    setState(() {
      _busy = false;
      _message = result?.granted == true
          ? reward == null
                ? context.tr('coin_added_wallet', const <Object>[0])
                : reward.isCoin
                ? context.tr('coin_added_wallet', <Object>[reward.amount])
                : context.tr('daily_hint_refill_reward')
          : widget.economyV3.error ?? context.tr('try_again');
    });
  }

  Future<void> _double() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await widget.economyV3.doubleLastDailyReward();
    await widget.economy.refresh(showLoading: false);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result?.granted == true
          ? context.tr('daily_reward_doubled')
          : widget.economyV3.error ?? context.tr('rewarded_ad_unavailable');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.economyV3.state;
    final calendar = state?.calendar ?? const <EconomyV3Reward>[];
    final cycleDay = state?.dailyCycleDay ?? 1;
    final completed = state == null
        ? 0
        : state.dailyAvailable
        ? cycleDay - 1
        : cycleDay;
    final canDouble =
        state?.canDoubleLastCoinReward == true && !widget.economy.noAds;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF081522),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFFFFC73D).withValues(alpha: .34),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 32,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const DuelAssetIcon(DuelAsset.dailyRewardPro, size: 54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('home_daily_reward_title'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            state?.nextDailyResetAt == null
                                ? context.tr('daily_reward_track_body')
                                : '${context.tr('time')}: ${DateFormat.Hm().format(state!.nextDailyResetAt!.toLocal())}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .66),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('close'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (calendar.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _RewardCalendar(
                    calendar: calendar,
                    cycleDay: cycleDay,
                    completedInCycle: completed,
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF29D398),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: state?.dailyAvailable == true && !_busy
                          ? _claim
                          : null,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.card_giftcard_rounded),
                      label: Text(
                        state?.nextReward.isHintRefill == true
                            ? context.tr('claim_hint_refill')
                            : context.tr('claim_daily_coin', <Object>[
                                state?.nextReward.amount ?? 0,
                              ]),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canDouble && !_busy ? _double : null,
                      icon: const Icon(Icons.ondemand_video_rounded),
                      label: Text(
                        context.tr('watch_ad_reward_value', <Object>[
                          state?.dailyLastClaimAmount ?? 0,
                        ]),
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
  }
}

class _RewardCalendar extends StatelessWidget {
  const _RewardCalendar({
    required this.calendar,
    required this.cycleDay,
    required this.completedInCycle,
  });

  final List<EconomyV3Reward> calendar;
  final int cycleDay;
  final int completedInCycle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 420 ? 6 : 5;
        final width = (constraints.maxWidth - ((columns - 1) * 7)) / columns;
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (var index = 0; index < calendar.length; index++)
              SizedBox(
                width: width,
                child: _RewardTile(
                  day: index + 1,
                  reward: calendar[index],
                  claimed: index + 1 <= completedInCycle,
                  current: index + 1 == cycleDay,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.day,
    required this.reward,
    required this.claimed,
    required this.current,
  });

  final int day;
  final EconomyV3Reward reward;
  final bool claimed;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final accent = current
        ? const Color(0xFFFFC73D)
        : claimed
        ? const Color(0xFF29D398)
        : const Color(0xFF66C7FF);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: current ? .30 : .18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: .38)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('daily_day_short', <Object>[day]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Icon(
              claimed
                  ? Icons.check_circle_rounded
                  : reward.isHintRefill
                  ? Icons.refresh_rounded
                  : Icons.monetization_on_rounded,
              color: accent,
              size: 17,
            ),
            const SizedBox(height: 3),
            Text(
              reward.isCoin
                  ? '${reward.amount}'
                  : context.tr('hint_refill_short'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.accent,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        fixedSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        backgroundColor: const Color(0xFF0A1728).withValues(alpha: .92),
        side: BorderSide(
          color: (accent ?? Colors.white).withValues(
            alpha: accent == null ? .13 : .34,
          ),
        ),
      ),
      icon: child,
    );
  }
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
                  : const DuelAssetIcon(DuelAsset.homePlayScene, size: 34),
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
    this.progress,
  });

  final String asset;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;
  final bool primary;
  final double? progress;
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
        height: compact ? 110 : 124,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _HomeModeTile(data: items[0], compact: compact),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HomeModeTile(data: items[1], compact: compact),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: compact ? 90 : 100,
          child: _HomeModeTile(data: items[0], compact: compact),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: compact ? 90 : 100,
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
    final itemHeight = compact ? 78.0 : 88.0;
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
        itemBuilder: (context, index) =>
            _HomeModeTile(data: items[index], compact: compact),
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
    final radius = data.primary ? 19.0 : 16.0;
    final artSize = data.primary
        ? compact
              ? 68.0
              : 78.0
        : compact
        ? 52.0
        : 60.0;

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
              horizontal: data.primary ? 10 : 8,
              vertical: data.primary ? 8 : 6,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  data.accent.withValues(alpha: data.primary ? .13 : .09),
                  const Color(0xFF0A1728).withValues(alpha: .97),
                ],
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: data.accent.withValues(alpha: data.primary ? .68 : .4),
                width: data.primary ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: data.accent.withValues(
                    alpha: data.primary ? .10 : .05,
                  ),
                  blurRadius: data.primary ? 18 : 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: artSize,
                  height: artSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(data.primary ? 18 : 14),
                    child: Center(
                      child: DuelAssetIcon(
                        data.asset,
                        size: artSize,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: data.primary ? 11 : 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: const StrutStyle(
                          forceStrutHeight: true,
                          height: 1.05,
                        ),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: data.primary
                              ? compact
                                    ? 15
                                    : 17
                              : compact
                              ? 12
                              : 13,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.subtitle,
                        maxLines: data.primary ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: data.accent.withValues(alpha: .88),
                          fontSize: data.primary ? 11 : 10,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (data.progress != null) ...[
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: data.progress!.clamp(0.0, 1.0).toDouble(),
                            minHeight: 4,
                            backgroundColor: Colors.white.withValues(
                              alpha: .08,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              data.accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: data.primary ? 28 : 24,
                  child: Center(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: .48),
                      size: data.primary ? 24 : 20,
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
      key: const ValueKey<String>('quick-play-dialog'),
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
                    const SizedBox(
                      width: 46,
                      height: 46,
                      child: Center(
                        child: DuelAssetIcon(DuelAsset.homePlayScene, size: 42),
                      ),
                    ),
                    const SizedBox(width: 9),
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
                const SizedBox(height: 8),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: SizedBox(
                      height: 122,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final chipWidth = (constraints.maxWidth - 12) / 3;
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final difficulty in SudokuDifficulty.values)
                              SizedBox(
                                width: chipWidth,
                                height: 42,
                                child: _DialogDifficultyCard(
                                  label: context.strings.difficultyLabel(
                                    difficulty,
                                  ),
                                  selected: _difficulty == difficulty,
                                  onTap: () =>
                                      setState(() => _difficulty = difficulty),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop((variant: _variant, difficulty: _difficulty)),
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
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: selected ? .2 : .07),
                const Color(0xFF0A1728),
              ],
            ),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: .12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 56,
                    child: Center(
                      child: DuelAssetIcon(
                        is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                        size: 52,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    variant.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    strutStyle: const StrutStyle(
                      forceStrutHeight: true,
                      height: 1.05,
                    ),
                    style: TextStyle(
                      color: selected ? accent : Colors.white,
                      fontSize: 15,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    is16 ? '1–16 · 256' : '1–9 · 81',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .6),
                      fontSize: 10.5,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: SizedBox.square(
                  dimension: 20,
                  child: selected
                      ? Icon(Icons.check_rounded, color: accent, size: 18)
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogDifficultyCard extends StatelessWidget {
  const _DialogDifficultyCard({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF29D398);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? accent : const Color(0xFF132438),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: .10),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? const Color(0xFF07111E) : Colors.white,
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
