import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../data/career_catalog.dart';
import '../../data/game_session_store.dart';
import '../../data/local_progress_store.dart';
import '../../data/samurai_game_session_store.dart';
import '../../data/ux_game_session_store.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/player_profile_service.dart';
import '../../services/platform_game_services.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';
import '../career/career_hub_screen.dart';
import '../duel/matchmaking_screen.dart';
import '../duel/pre_match_ready_screen.dart';
import '../economy/coin_store_screen.dart';
import '../game/enhanced_game_screen.dart';
import '../game/samurai_game_screen.dart';
import '../settings/ux_settings_screen.dart';
import '../social/profile_hub_screen.dart';
import '../social/social_hub_screen.dart';
import '../social/ux_challenge_invitation_screen.dart';

class UxRootScreen extends StatefulWidget {
  const UxRootScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<UxRootScreen> createState() => _UxRootScreenState();
}

class _UxRootScreenState extends State<UxRootScreen> {
  final EconomyService _economy = EconomyService.instance;
  final PushNotificationService _push = PushNotificationService.instance;
  final UxGameSessionStore _sessions = UxGameSessionStore.instance;
  final GameSessionStore _legacySessions = GameSessionStore.instance;
  final SamuraiGameSessionStore _samuraiSessions =
      SamuraiGameSessionStore.instance;

  PlayerProfilePreferences? _profile;
  UxGameSession? _activeSession;
  ActiveGameSessionMetadata? _legacySession;
  SamuraiGameSession? _samuraiSession;
  int _socialBadge = 0;
  bool _routingPush = false;
  bool _openingSession = false;
  bool _identityBusy = false;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_refresh);
    _sessions.activeSession.addListener(_sessionChanged);
    _legacySessions.activeSession.addListener(_legacySessionChanged);
    _samuraiSessions.activeSession.addListener(_samuraiSessionChanged);
    _push.openedChallengeId.addListener(_schedulePushRouting);
    _push.openedRematchId.addListener(_schedulePushRouting);
    unawaited(_economy.initialize());
    unawaited(_sessions.initialize());
    unawaited(_legacySessions.latest());
    unawaited(_samuraiSessions.initialize());
    unawaited(_loadProfile());
    unawaited(_loadBadge());
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePushRouting());
  }

  @override
  void dispose() {
    _economy.removeListener(_refresh);
    _sessions.activeSession.removeListener(_sessionChanged);
    _legacySessions.activeSession.removeListener(_legacySessionChanged);
    _samuraiSessions.activeSession.removeListener(_samuraiSessionChanged);
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

  void _legacySessionChanged() {
    if (mounted) {
      setState(() => _legacySession = _legacySessions.activeSession.value);
    }
  }

  void _samuraiSessionChanged() {
    if (mounted) {
      setState(() => _samuraiSession = _samuraiSessions.activeSession.value);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await PlayerProfileService.instance.load();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // Offline Sudoku remains usable without an online profile.
    }
  }

  Future<void> _loadBadge() async {
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
      // Badge is optional and should not turn an offline home into an error.
    }
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
      if (!await _ensureOnlineIdentity()) return;
      if (!mounted) return;
      if (challengeId != null && challengeId.isNotEmpty) {
        _push.openedChallengeId.value = null;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                UxChallengeInvitationScreen(challengeId: challengeId),
          ),
        );
      } else if (rematchId != null && rematchId.isNotEmpty) {
        _push.openedRematchId.value = null;
        await _openRematch(rematchId);
      }
    } finally {
      if (mounted) {
        setState(() => _routingPush = false);
        await _refreshAfterRoute();
        if (_push.openedChallengeId.value != null ||
            _push.openedRematchId.value != null) {
          _schedulePushRouting();
        }
      }
    }
  }

  Future<bool> _ensureOnlineIdentity() async {
    if (_identityBusy) return false;
    if (!SocialApiClient.instance.configured) {
      _snack(context.tr('friend_requests_setup_required'));
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
      final profile = await PlayerProfileService.instance.load();
      if (!mounted) return false;
      setState(() => _profile = profile);
      if (profile.profileConfirmed) return true;

      final value = await _showIdentityDialog(profile);
      if (value == null) return false;
      final updated = await PlayerProfileService.instance.update(
        username: value.username,
        displayName: value.displayName,
        discoverable: true,
        nameSource: 'custom',
      );
      if (mounted) setState(() => _profile = updated);
      return true;
    } on PlayerProfileException catch (error) {
      if (mounted) _snack(UserSafeError.message(context, error));
      return false;
    } on SocialApiException catch (error) {
      if (mounted) _snack(UserSafeError.message(context, error));
      return false;
    } catch (_) {
      if (mounted) _snack(context.tr('try_again_when_connected'));
      return false;
    } finally {
      if (mounted) setState(() => _identityBusy = false);
    }
  }

  Future<({String username, String displayName})?> _showIdentityDialog(
    PlayerProfilePreferences profile,
  ) async {
    final display = TextEditingController(
      text: profile.displayName == 'Sudoku Player' ? '' : profile.displayName,
    );
    final username = TextEditingController(text: profile.username);
    final result = await showDialog<({String username, String displayName})>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = username.text.trim().toLowerCase();
          final valid =
              display.text.trim().length >= 2 &&
              RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalized);
          return AlertDialog(
            title: Text(context.tr('create_player_profile')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.tr('create_player_profile_body')),
                    const SizedBox(height: 14),
                    TextField(
                      controller: display,
                      autofocus: true,
                      maxLength: 24,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: context.tr('display_name'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: username,
                      maxLength: 20,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[a-zA-Z0-9_]'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: context.tr('unique_username'),
                        helperText: context.tr('username_helper'),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('friend_id_value', <Object>[profile.publicId]),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.tr('cancel')),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.of(dialogContext).pop((
                        username: normalized,
                        displayName: display.text.trim(),
                      ))
                    : null,
                child: Text(context.tr('continue_action')),
              ),
            ],
          );
        },
      ),
    );
    display.dispose();
    username.dispose();
    return result;
  }

  Future<void> _openRematch(String invitationId) async {
    try {
      await _economy.refresh(showLoading: false);
      final invitations = await _economy.loadRematches();
      RematchInvitation? invitation;
      for (final item in invitations) {
        if (item.id == invitationId) {
          invitation = item;
          break;
        }
      }
      if (!mounted) return;
      if (invitation == null ||
          !invitation.isPending ||
          invitation.isSender ||
          invitation.expiresAt.isBefore(DateTime.now())) {
        _snack(context.tr('challenge_timed_out'));
        return;
      }
      final response = await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        builder: (_) => _RematchSheet(invitation: invitation!),
      );
      if (!mounted || response == null) return;
      final updated = await _economy.respondRematch(
        invitationId: invitation.id,
        accept: response,
      );
      if (!mounted) return;
      if (response && updated.roomId?.isNotEmpty == true) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => PreMatchReadyScreen(roomId: updated.roomId!),
          ),
        );
      } else {
        _snack(
          response
              ? context.tr('rematch_could_not_start')
              : context.tr('rematch_declined'),
        );
      }
    } on EconomyApiException catch (error) {
      if (mounted) _snack(UserSafeError.message(context, error));
    } catch (_) {
      if (mounted) _snack(context.tr('rematch_invitation_load_failed'));
    }
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

  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));
    await _refreshAfterRoute();
  }

  Future<void> _refreshAfterRoute() async {
    await Future.wait<void>([
      _economy.refresh(showLoading: false),
      _sessions.latest().then((_) {}),
      _legacySessions.latest().then((_) {}),
      _samuraiSessions.initialize(),
      _loadProfile(),
      _loadBadge(),
    ]);
  }

  Future<void> _resume() async {
    if (_openingSession) return;
    setState(() => _openingSession = true);
    try {
      final session = _activeSession;
      if (session != null) {
        await _resumeUxSession(session);
      } else if (_samuraiSession != null) {
        await _resumeSamurai(_samuraiSession!);
      } else if (_legacySession != null) {
        await _resumeLegacy(_legacySession!);
      }
    } finally {
      if (mounted) {
        setState(() => _openingSession = false);
        await _refreshAfterRoute();
      }
    }
  }

  Future<void> _resumeUxSession(UxGameSession session) async {
    final level = CareerCatalog.byId(session.puzzle.id);
    final wasCompleted = level == null
        ? widget.store.isCompleted(session.puzzle.id)
        : widget.store.isCompleted(level.id);
    final result = await Navigator.of(context).push<EnhancedGameExit>(
      MaterialPageRoute(
        builder: (gameContext) => EnhancedGameScreen(
          puzzle: session.puzzle,
          store: widget.store,
          showNextAction: level != null,
          completionTitle: level == null
              ? null
              : gameContext.tr('level_title', <Object>[
                  gameContext.strings.difficultyLabel(level.difficulty),
                  level.number,
                ]),
          onCompleted:
              ({required seconds, required mistakes, required hints}) async {
                final id = level?.id ?? session.puzzle.id;
                await widget.store.recordResult(
                  puzzleId: id,
                  seconds: seconds,
                  mistakes: mistakes,
                  hints: hints,
                );
                if (level != null && !wasCompleted && level.hintReward > 0) {
                  await widget.store.addHints(level.hintReward);
                }
                await _claimEligibleAchievements();
              },
        ),
      ),
    );
    if (!mounted) return;
    if (result == EnhancedGameExit.next && level != null) {
      await _open(CareerHubScreen(store: widget.store));
    }
  }

  Future<void> _resumeSamurai(SamuraiGameSession session) async {
    await Navigator.of(context).push<SamuraiGameExit>(
      MaterialPageRoute(
        builder: (_) => SamuraiGameScreen(
          puzzle: session.puzzle,
          initialSession: session,
          store: widget.store,
          onCompleted:
              ({required seconds, required mistakes, required hints}) async {
                await widget.store.recordResult(
                  puzzleId:
                      'practice-samurai-${session.puzzle.difficulty.name}',
                  seconds: seconds,
                  mistakes: mistakes,
                  hints: hints,
                );
                await _claimEligibleAchievements();
              },
        ),
      ),
    );
  }

  Future<void> _resumeLegacy(ActiveGameSessionMetadata metadata) async {
    final level = CareerCatalog.byId(metadata.puzzleId);
    if (level == null) {
      await _legacySessions.clearAll();
      return;
    }
    final puzzle = await Future<SudokuPuzzle>(
      () => CareerCatalog.puzzleFor(level),
    );
    if (!mounted) return;
    final wasCompleted = widget.store.isCompleted(level.id);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (gameContext) => EnhancedGameScreen(
          puzzle: puzzle,
          store: widget.store,
          completionTitle: gameContext.tr('level_title', <Object>[
            gameContext.strings.difficultyLabel(level.difficulty),
            level.number,
          ]),
          mistakeLimit: 3,
          onCompleted:
              ({required seconds, required mistakes, required hints}) async {
                await widget.store.recordResult(
                  puzzleId: level.id,
                  seconds: seconds,
                  mistakes: mistakes,
                  hints: hints,
                );
                if (!wasCompleted && level.hintReward > 0) {
                  await widget.store.addHints(level.hintReward);
                }
                await _claimEligibleAchievements();
              },
        ),
      ),
    );
  }

  Future<void> _claimEligibleAchievements() async {
    await _unlockPlatformFirstGrid();
    const achievements = <String>[
      'first_win',
      'games_25',
      'wins_10',
      'wins_50',
      'rating_1200',
      'rating_1500',
      'wins_250',
    ];
    for (final achievement in achievements) {
      try {
        await _economy.claimAchievement(achievement);
      } catch (error) {
        debugPrint('Achievement claim skipped for $achievement: $error');
      }
    }
  }

  Future<void> _unlockPlatformFirstGrid() async {
    try {
      if (await PlatformGameServices.instance.refreshAuthentication()) {
        await PlatformGameServices.instance.unlockAchievement();
      }
    } catch (error) {
      debugPrint('Platform first-grid achievement unlock failed: $error');
    }
  }

  Future<void> _claimDaily() async {
    final claimed = await _economy.claimDailyLogin();
    if (!mounted) return;
    _snack(
      claimed
          ? context.tr('coin_added_wallet', <Object>[
              _economy.wallet?.dailyLoginAmount ?? 50,
            ])
          : _economy.error ?? context.tr('try_again'),
    );
  }

  Future<void> _claimDailyAd() async {
    final claimed = await _economy.claimDailyRewardedAd();
    if (!mounted) return;
    _snack(
      claimed
          ? context.tr('coin_added_wallet', <Object>[
              _economy.wallet?.dailyAdAmount ?? 50,
            ])
          : _economy.error ?? context.tr('rewarded_ad_unavailable'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resume = _activeSession;
    final samurai = _samuraiSession;
    final legacyLevel = _legacySession == null
        ? null
        : CareerCatalog.byId(_legacySession!.puzzleId);
    final rewardReady =
        _economy.wallet?.dailyLoginAvailable == true ||
        (_economy.wallet?.dailyAdAvailable == true && !_economy.noAds);
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshAfterRoute,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                      children: [
                        _TopBar(
                          profile: _profile,
                          balance: _economy.balance,
                          badge: _socialBadge,
                          onProfile: _openProfile,
                          onSocial: _openSocial,
                          onSettings: () =>
                              _open(UxSettingsScreen(store: widget.store)),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          context.tr('app_name').toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        if (resume != null ||
                            samurai != null ||
                            legacyLevel != null) ...[
                          _ResumeCard(
                            title: resume != null
                                ? _sessionTitle(context, resume)
                                : samurai != null
                                ? '${context.tr('samurai_sudoku')} · ${context.strings.difficultyLabel(samurai.puzzle.difficulty)}'
                                : context.tr('level_title', <Object>[
                                    context.strings.difficultyLabel(
                                      legacyLevel!.difficulty,
                                    ),
                                    legacyLevel.number,
                                  ]),
                            elapsed:
                                resume?.elapsedSeconds ??
                                samurai?.elapsedSeconds ??
                                _legacySession!.elapsedSeconds,
                            loading: _openingSession,
                            onTap: _resume,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _FeatureCard(
                          icon: DuelAsset.homeDuelEmblem,
                          title: context.tr('online_duel'),
                          subtitle: context.tr('online_duel_subtitle'),
                          accent: const Color(0xFF29D398),
                          prominent: true,
                          onTap: _identityBusy ? null : _openOnline,
                        ),
                        const SizedBox(height: 12),
                        _FeatureCard(
                          icon: DuelAsset.homeCareerRelic,
                          title: context.tr('career'),
                          subtitle: context.tr('career_subtitle'),
                          accent: const Color(0xFFFFC94D),
                          trailing: context.tr('completed_levels', <Object>[
                            widget.store.completedCareerLevelCount,
                          ]),
                          onTap: () =>
                              _open(CareerHubScreen(store: widget.store)),
                        ),
                        const SizedBox(height: 12),
                        _FeatureCard(
                          icon: DuelAsset.people,
                          title: context.tr('friends_challenges'),
                          subtitle: context.tr('friend_requests'),
                          accent: const Color(0xFF3AA9FF),
                          trailing: _socialBadge > 0 ? '$_socialBadge' : null,
                          onTap: _identityBusy ? null : _openSocial,
                        ),
                        if (rewardReady) ...[
                          const SizedBox(height: 12),
                          _DailyRewardCard(
                            economy: _economy,
                            onLogin: _claimDaily,
                            onAd: _claimDailyAd,
                          ),
                        ],
                        const SizedBox(height: 12),
                        _FeatureCard(
                          icon: DuelAsset.homeStoreChest,
                          title: context.tr('coin_store'),
                          subtitle: context.tr('home_daily_reward_body'),
                          accent: const Color(0xFF29D398),
                          trailing: NumberFormat.compact().format(
                            _economy.balance,
                          ),
                          onTap: () => _open(const CoinStoreScreen()),
                        ),
                        const SizedBox(height: 12),
                        _FeatureCard(
                          icon: DuelAsset.homeProfileCrest,
                          title: context.tr('profile'),
                          subtitle: context.tr('shown_to_other_players'),
                          accent: const Color(0xFF7A5CFF),
                          onTap: _identityBusy ? null : _openProfile,
                        ),
                        if (_economy.error != null) ...[
                          const SizedBox(height: 12),
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: ListTile(
                              leading: const Icon(Icons.cloud_off_outlined),
                              title: Text(_economy.error!),
                              trailing: IconButton(
                                tooltip: context.tr('retry'),
                                onPressed: _refreshAfterRoute,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _sessionTitle(BuildContext context, UxGameSession session) {
    final level = CareerCatalog.byId(session.puzzle.id);
    if (level != null) {
      return context.tr('level_title', <Object>[
        context.strings.difficultyLabel(level.difficulty),
        level.number,
      ]);
    }
    if (session.mode == 'daily') return context.tr('daily_sudoku');
    return '${context.tr('practice')} · ${context.strings.difficultyLabel(session.puzzle.difficulty)}';
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.profile,
    required this.balance,
    required this.badge,
    required this.onProfile,
    required this.onSocial,
    required this.onSettings,
  });

  final PlayerProfilePreferences? profile;
  final int balance;
  final int badge;
  final VoidCallback onProfile;
  final VoidCallback onSocial;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? 'Sudoku Player';
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onProfile,
            borderRadius: BorderRadius.circular(999),
            child: Row(
              children: [
                PlayerAvatar(
                  displayName: name,
                  avatarKey: 'home-$name',
                  radius: 20,
                  semanticLabel: context.tr('player_avatar_semantics', <Object>[
                    name,
                  ]),
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
        _CircleAction(
          tooltip: context.tr('friends_challenges'),
          onTap: onSocial,
          child: Badge(
            isLabelVisible: badge > 0,
            label: Text('$badge'),
            child: const Icon(Icons.people_outline_rounded),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFFFC94D).withValues(alpha: .3),
            ),
          ),
          child: Row(
            children: [
              const DuelAssetIcon(
                DuelAsset.coin,
                size: 18,
                color: Color(0xFFFFC94D),
              ),
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
        const SizedBox(width: 6),
        _CircleAction(
          tooltip: context.tr('settings'),
          onTap: onSettings,
          child: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: Colors.black.withValues(alpha: .34),
        side: BorderSide(color: Colors.white.withValues(alpha: .14)),
      ),
      icon: child,
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.title,
    required this.elapsed,
    required this.loading,
    required this.onTap,
  });

  final String title;
  final int elapsed;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF173127).withValues(alpha: .96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: const Color(0xFF29D398).withValues(alpha: .48)),
      ),
      child: ListTile(
        minTileHeight: 82,
        onTap: loading ? null : onTap,
        leading: loading
            ? const SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.play_circle_fill_rounded,
                color: Color(0xFF29D398),
                size: 42,
              ),
        title: Text(
          context.tr('continue_action'),
          style: const TextStyle(
            color: Color(0xFF29D398),
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          '$title · ${formatDuration(elapsed)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_rounded),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.trailing,
    this.prominent = false,
  });

  final String icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;
  final String? trailing;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF101B20).withValues(alpha: .96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(prominent ? 26 : 20),
        side: BorderSide(color: accent.withValues(alpha: prominent ? .5 : .28)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(prominent ? 26 : 20),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: prominent ? 20 : 15,
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: prominent ? 68 : 54,
                child: DuelAssetIcon(icon, size: prominent ? 58 : 44),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: prominent ? 21 : 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .66),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailing!,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w900),
                ),
              ],
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyRewardCard extends StatelessWidget {
  const _DailyRewardCard({
    required this.economy,
    required this.onLogin,
    required this.onAd,
  });

  final EconomyService economy;
  final VoidCallback onLogin;
  final VoidCallback onAd;

  @override
  Widget build(BuildContext context) {
    final wallet = economy.wallet;
    return Card(
      color: const Color(0xFF14231D).withValues(alpha: .96),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('home_daily_reward_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (wallet?.dailyLoginAvailable == true)
                  FilledButton.icon(
                    onPressed: economy.claimingDaily ? null : onLogin,
                    icon: const Icon(Icons.card_giftcard_rounded),
                    label: Text(
                      context.tr('claim_daily_coin', <Object>[
                        wallet!.dailyLoginAmount,
                      ]),
                    ),
                  ),
                if (wallet?.dailyAdAvailable == true && !economy.noAds)
                  OutlinedButton.icon(
                    onPressed: economy.showingDailyAd ? null : onAd,
                    icon: const Icon(Icons.ondemand_video_outlined),
                    label: Text(
                      context.tr('watch_ad_for_coin', <Object>[
                        wallet!.dailyAdAmount,
                      ]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RematchSheet extends StatefulWidget {
  const _RematchSheet({required this.invitation});

  final RematchInvitation invitation;

  @override
  State<_RematchSheet> createState() => _RematchSheetState();
}

class _RematchSheetState extends State<_RematchSheet> {
  final EconomyService _economy = EconomyService.instance;
  Timer? _timer;

  int get _seconds => widget.invitation.expiresAt
      .difference(DateTime.now())
      .inSeconds
      .clamp(0, 99);

  int get _fee => _economy.entryFeeForDifficulty(widget.invitation.difficulty);

  bool get _canAccept => _seconds > 0 && _economy.balance >= _fee;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_refresh);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_seconds <= 0) {
        Navigator.of(context).pop();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _economy.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _store() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const CoinStoreScreen()));
    await _economy.refresh(showLoading: false);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('rematch_invitation_title'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('wants_to_play_again', <Object>[
              widget.invitation.sender.displayName,
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('seconds_value', <Object>[_seconds]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '${context.tr('rematch_requires_coin', <Object>[_fee])} ${context.tr('balance_coin', <Object>[_economy.balance])}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (!_canAccept)
            OutlinedButton.icon(
              onPressed: _store,
              icon: const Icon(Icons.storefront_outlined),
              label: Text(context.tr('open_coin_store')),
            ),
          if (!_canAccept) const SizedBox(height: 8),
          FilledButton(
            onPressed: _canAccept
                ? () => Navigator.of(context).pop(true)
                : null,
            child: Text(context.tr('accept')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('decline')),
          ),
        ],
      ),
    );
  }
}
