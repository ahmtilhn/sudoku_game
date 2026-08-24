import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/career_catalog.dart';
import '../../data/game_session_store.dart';
import '../../data/local_progress_store.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
import '../../services/platform_game_services.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/duel_asset_icon.dart';
import '../game/game_screen.dart';
import '../game/hint_economy.dart';
import 'challenge_invitation_screen.dart';
import 'player_identity_gate.dart';

class ChallengeNavigationGate extends StatefulWidget {
  const ChallengeNavigationGate({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<ChallengeNavigationGate> createState() =>
      _ChallengeNavigationGateState();
}

class _ChallengeNavigationGateState extends State<ChallengeNavigationGate> {
  final PushNotificationService _push = PushNotificationService.instance;
  final GameSessionStore _sessions = GameSessionStore.instance;
  final EconomyService _economy = EconomyService.instance;

  ActiveGameSessionMetadata? _activeSession;
  bool _openingChallenge = false;
  bool _challengeOpenScheduled = false;
  bool _launchingSession = false;

  @override
  void initState() {
    super.initState();
    _push.openedChallengeId.addListener(_scheduleChallengeOpen);
    _sessions.activeSession.addListener(_onActiveSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleChallengeOpen();
      unawaited(_sessions.latest());
    });
  }

  @override
  void dispose() {
    _push.openedChallengeId.removeListener(_scheduleChallengeOpen);
    _sessions.activeSession.removeListener(_onActiveSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    final pendingChallenge = _push.openedChallengeId.value?.isNotEmpty == true;
    if (routeIsCurrent && pendingChallenge && !_openingChallenge) {
      _scheduleChallengeOpen();
    }

    final metadata = _activeSession;
    final level = metadata == null
        ? null
        : CareerCatalog.byId(metadata.puzzleId);
    final showResume =
        level != null &&
        !_openingChallenge &&
        !_launchingSession &&
        routeIsCurrent;

    return Stack(
      children: [
        PlayerIdentityGate(store: widget.store),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: showResume
                      ? _ActiveCareerSessionCard(
                          key: ValueKey(metadata!.puzzleId),
                          level: level,
                          elapsedSeconds: metadata.elapsedSeconds,
                          onTap: () => _resumeCareer(level),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onActiveSessionChanged() {
    if (!mounted) return;
    final metadata = _sessions.activeSession.value;
    final careerLevel = metadata == null
        ? null
        : CareerCatalog.byId(metadata.puzzleId);
    setState(() => _activeSession = careerLevel == null ? null : metadata);
  }

  void _scheduleChallengeOpen() {
    if (_challengeOpenScheduled || !mounted) return;
    _challengeOpenScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _challengeOpenScheduled = false;
      if (mounted) unawaited(_openChallenge());
    });
  }

  Future<void> _openChallenge() async {
    if (!mounted ||
        _openingChallenge ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    final challengeId = _push.openedChallengeId.value;
    if (challengeId == null || challengeId.isEmpty) return;

    setState(() => _openingChallenge = true);
    _push.openedChallengeId.value = null;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChallengeInvitationScreen(challengeId: challengeId),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingChallenge = false);
        unawaited(_sessions.latest());
        if (_push.openedChallengeId.value != null) _scheduleChallengeOpen();
      }
    }
  }

  Future<void> _resumeCareer(CareerLevel level) async {
    if (_launchingSession) return;
    setState(() => _launchingSession = true);

    SudokuPuzzle puzzle;
    try {
      puzzle = await Future<SudokuPuzzle>(() => CareerCatalog.puzzleFor(level));
    } catch (_) {
      if (!mounted) return;
      setState(() => _launchingSession = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('matchmaking_start_failed'))),
      );
      return;
    }

    if (!mounted) return;
    final wasCompleted = widget.store.isCompleted(level.id);
    setState(() => _launchingSession = false);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (gameContext) => GameScreen(
          puzzle: puzzle,
          completionTitle: gameContext.tr('level_title', <Object>[
            gameContext.strings.difficultyLabel(level.difficulty),
            level.number,
          ]),
          mistakeLimit: 3,
          coinContinueCost: 25,
          onCoinContinue: (_) => _economy.spendCareerContinue(),
          onRewardedContinue: AdsService.instance.showRewarded,
          onConsumeHint: () =>
              HintEconomy.consumeOrAcquire(gameContext, widget.store),
          hintBalanceProvider: () => widget.store.hints,
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
    if (mounted) unawaited(_sessions.latest());
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
}

class _ActiveCareerSessionCard extends StatelessWidget {
  const _ActiveCareerSessionCard({
    super.key,
    required this.level,
    required this.elapsedSeconds,
    required this.onTap,
  });

  final CareerLevel level;
  final int elapsedSeconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF29D398);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      elevation: 12,
      shadowColor: Colors.black54,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: .22),
                const Color(0xFF071014).withValues(alpha: .98),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: .48)),
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: .14),
                  border: Border.all(color: accent.withValues(alpha: .34)),
                ),
                child: const SizedBox.square(
                  dimension: 48,
                  child: DuelAssetIcon(
                    DuelAsset.grid,
                    size: 27,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('continue_action'),
                      style: const TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('level_title', <Object>[
                        context.strings.difficultyLabel(level.difficulty),
                        level.number,
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatDuration(elapsedSeconds),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .60),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const DuelAssetIcon(
                DuelAsset.arrowForward,
                size: 21,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
