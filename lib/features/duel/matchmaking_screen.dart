import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/user_safe_error.dart';
import '../../data/local_progress_store.dart';
import '../../domain/classic16_puzzle_factory.dart';
import '../../domain/sudoku.dart';
import '../../domain/sudoku_variant.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/firebase_session_service.dart';
import '../../services/social_api_client.dart';
import '../../services/variant_matchmaking_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../economy/coin_store_screen.dart';
import '../game/enhanced_game_screen.dart';
import 'matchmaking_stage.dart';
import 'pre_match_ready_screen.dart';

class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({
    super.key,
    this.initialDifficulty,
    this.initialVariant = SudokuVariant.classic9,
  });

  final SudokuDifficulty? initialDifficulty;
  final SudokuVariant initialVariant;

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  final EconomyService _economy = EconomyService.instance;
  final VariantMatchmakingClient _matchmaking = VariantMatchmakingClient.instance;

  late SudokuDifficulty _difficulty;
  late SudokuVariant _variant;
  CompetitiveProfile? _profile;
  bool _searching = false;
  bool _polling = false;
  bool _cancelling = false;
  bool _openingRoom = false;
  Timer? _pollTimer;
  int _pollAttempt = 0;
  int? _queueRating;
  String? _searchStatus;
  Future<VariantMatchmakingResult>? _activeQueueRequest;

  int get _entryFee => _economy.entryFeeForDifficulty(_difficulty.name);
  bool get _canEnter => _economy.balance >= _entryFee;

  @override
  void initState() {
    super.initState();
    _difficulty = widget.initialDifficulty ?? SudokuDifficulty.easy;
    _variant = widget.initialVariant;
    _economy.addListener(_refresh);
    unawaited(_economy.initialize());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_searching && !_openingRoom) {
      unawaited(_matchmaking.cancelRankedQueue());
    }
    _economy.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_searching) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_cancelSearch());
        },
        child: MatchmakingStage(
          currentPlayer: _currentVisualPlayer(context),
          actionLabel: context.tr('cancel_search'),
          actionIcon: Icons.close_rounded,
          actionBusy: _cancelling,
          onAction: _cancelling ? null : _cancelSearch,
          onClose: _cancelling ? null : _cancelSearch,
          searchStatus: _cancelling
              ? context.tr('cancel_search')
              : _searchStatus,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              final horizontal = constraints.maxWidth >= 760;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
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
                        _Header(
                          balance: _economy.balance,
                          onBack: () => Navigator.of(context).pop(),
                          onStore: _openStore,
                        ),
                        SizedBox(height: compact ? 6 : 10),
                        Text(
                          context.tr('online_duel'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 23 : 27,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.tr('same_difficulty_match'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .64),
                            fontSize: compact ? 12 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: compact ? 9 : 12),
                        if (horizontal)
                          SizedBox(
                            height: compact ? 116 : 124,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _variantSection(compact)),
                                const SizedBox(width: 10),
                                Expanded(child: _difficultySection(compact)),
                              ],
                            ),
                          )
                        else ...[
                          SizedBox(
                            height: compact ? 82 : 90,
                            child: _variantSection(compact),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: compact ? 104 : 112,
                            child: _difficultySection(compact),
                          ),
                        ],
                        const Spacer(),
                        _EntryBar(
                          fee: _entryFee,
                          pot: _economy.winnerPotForDifficulty(_difficulty.name),
                          variant: _variant,
                        ),
                        SizedBox(height: compact ? 8 : 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openLocalPractice,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: Size(0, compact ? 46 : 50),
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: .24),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.sports_esports_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  context.tr('local_practice'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: _economy.loading
                                    ? null
                                    : _canEnter
                                        ? _findOpponent
                                        : _showInsufficientCoins,
                                style: FilledButton.styleFrom(
                                  minimumSize: Size(0, compact ? 46 : 50),
                                  backgroundColor: _canEnter
                                      ? const Color(0xFF29D398)
                                      : const Color(0xFFFFC73D),
                                  foregroundColor: const Color(0xFF07111E),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: Icon(
                                  _canEnter
                                      ? Icons.travel_explore_rounded
                                      : Icons.lock_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  _canEnter
                                      ? context.tr('find_opponent')
                                      : context.tr('open_coin_store'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
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

  MatchmakingVisualPlayer _currentVisualPlayer(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return MatchmakingVisualPlayer(
        displayName: context.tr('you'),
        avatarKey: 'matchmaking-you',
        rating: _queueRating,
      );
    }
    return MatchmakingVisualPlayer(
      displayName: profile.displayName,
      avatarKey: profile.avatarKey,
      rankLabel: profile.rankName,
      gamesPlayed: profile.wins + profile.losses + profile.draws,
      winRate: profile.winRate,
      rating: _queueRating ?? profile.currentElo,
    );
  }

  Widget _variantSection(bool compact) {
    return _SectionCard(
      title: 'Sudoku',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final variant in SudokuVariant.values) ...[
            Expanded(
              child: _VariantCard(
                variant: variant,
                selected: _variant.id == variant.id,
                compact: compact,
                onTap: () => setState(() => _variant = variant),
              ),
            ),
            if (variant != SudokuVariant.values.last) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _difficultySection(bool compact) {
    return _SectionCard(
      title: context.tr('choose_duel_difficulty'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final buttonWidth = (constraints.maxWidth - 12) / 3;
          return Align(
            alignment: Alignment.topCenter,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              children: [
                for (final difficulty in SudokuDifficulty.values)
                  SizedBox(
                    width: buttonWidth,
                    height: compact ? 30 : 34,
                    child: ChoiceChip(
                      selected: _difficulty == difficulty,
                      onSelected: (_) {
                        setState(() => _difficulty = difficulty);
                      },
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(
                          context.strings.difficultyLabel(difficulty),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      showCheckmark: false,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      selectedColor: const Color(0xFF29D398),
                      backgroundColor: const Color(0xFF122234),
                      labelStyle: TextStyle(
                        color: _difficulty == difficulty
                            ? const Color(0xFF07111E)
                            : Colors.white,
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w900,
                      ),
                      side: BorderSide(
                        color: _difficulty == difficulty
                            ? const Color(0xFF29D398)
                            : Colors.white.withValues(alpha: .14),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openLocalPractice() async {
    final store = await LocalProgressStore.create();
    final puzzle = _variant.id == SudokuVariantId.classic16
        ? Classic16PuzzleFactory.generate(difficulty: _difficulty)
        : SudokuEngine.generate(difficulty: _difficulty, size: 9);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EnhancedGameScreen(
          puzzle: puzzle,
          store: store,
          allowNotes: true,
          showNextAction: false,
          onCompleted: ({required seconds, required mistakes, required hints}) =>
              store.recordResult(
                puzzleId: puzzle.id,
                seconds: seconds,
                mistakes: mistakes,
                hints: hints,
                variant: _variant,
              ),
        ),
      ),
    );
  }

  Future<void> _openStore() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CoinStoreScreen()),
    );
    await _economy.refresh(showLoading: false);
  }

  Future<void> _showInsufficientCoins() async {
    await _economy.refresh();
    if (!mounted) return;
    if (_canEnter) {
      await _findOpponent();
      return;
    }
    final openStore = await GameModal.warning(
      context,
      title: context.tr('coin_required_title_dynamic', <Object>[_entryFee]),
      message: context.tr('coin_required_body_dynamic', <Object>[
        _entryFee,
        _economy.winnerPotForDifficulty(_difficulty.name),
      ]),
      confirmLabel: context.tr('open_coin_store'),
      cancelLabel: context.tr('cancel'),
    );
    if (openStore && mounted) await _openStore();
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final profile = await SocialApiClient.instance.loadCompetitiveProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // Matchmaking can continue with the authenticated room identity fallback.
    }
  }

  Future<void> _findOpponent() async {
    if (_searching || _openingRoom) return;
    await _economy.refresh();
    if (!mounted) return;
    if (!_canEnter) {
      await _showInsufficientCoins();
      return;
    }

    setState(() {
      _searching = true;
      _cancelling = false;
      _searchStatus = null;
      _queueRating = null;
      _pollAttempt = 0;
    });

    try {
      await FirebaseSessionService.ensureAnonymousSession();
      unawaited(_loadCurrentProfile());
      final result = await _joinSelectedQueue();
      if (!mounted || !_searching) return;
      _queueRating = result.rating;
      if (result.matched) {
        _openMatchedResult(result);
        return;
      }
      if (result.status != 'queued') {
        throw const SocialApiException(
          0,
          'Unexpected matchmaking response.',
        );
      }
      if (mounted) setState(() {});
      _startPolling();
    } on FirebaseSessionException catch (error) {
      await _stopWithError(UserSafeError.message(context, error));
    } on SocialApiException catch (error) {
      if (error.statusCode == 409) {
        await _economy.refresh(showLoading: false);
      }
      if (mounted) {
        await _stopWithError(UserSafeError.message(context, error));
      }
    } catch (_) {
      if (mounted) {
        await _stopWithError(context.tr('matchmaking_start_failed'));
      }
    }
  }

  Future<VariantMatchmakingResult> _joinSelectedQueue() async {
    late final Future<VariantMatchmakingResult> request;
    request = _matchmaking
        .joinRankedQueue(
          difficulty: _difficulty.name,
          variant: _variant,
        )
        .then((result) {
          if (result.variant.id != _variant.id ||
              result.boardSize != _variant.boardSize ||
              result.cellCount != _variant.cellCount) {
            throw const SocialApiException(
              409,
              'The matchmaking room does not match the selected Sudoku size.',
            );
          }
          return result;
        });
    _activeQueueRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_activeQueueRequest, request)) {
        _activeQueueRequest = null;
      }
    }
  }

  void _openMatchedResult(VariantMatchmakingResult result) {
    if (_openingRoom) return;
    final roomId = result.roomId?.trim() ?? '';
    if (roomId.isEmpty) {
      unawaited(_stopWithError(context.tr('matchmaking_start_failed')));
      return;
    }
    if (_variant.id == SudokuVariantId.classic16 &&
        !roomId.startsWith('classic16:')) {
      unawaited(_stopWithError(context.tr('matchmaking_start_failed')));
      return;
    }
    if (_variant.id == SudokuVariantId.classic9 &&
        roomId.startsWith('classic16:')) {
      unawaited(_stopWithError(context.tr('matchmaking_start_failed')));
      return;
    }
    _openOnlineRoom(roomId);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollAttempt = 0;
    _scheduleNextPoll(immediate: true);
  }

  void _scheduleNextPoll({bool immediate = false}) {
    _pollTimer?.cancel();
    if (!_searching || _cancelling || !mounted) return;
    final delay = immediate
        ? Duration.zero
        : matchmakingFallbackDelay(_pollAttempt++);
    _pollTimer = Timer(delay, () => unawaited(_pollForMatch()));
  }

  Future<void> _pollForMatch() async {
    if (!_searching || _polling || _cancelling) return;
    _polling = true;
    try {
      final result = await _joinSelectedQueue();
      if (!mounted || !_searching) return;
      _queueRating = result.rating ?? _queueRating;
      if (result.matched) {
        _openMatchedResult(result);
        return;
      }
      if (_searchStatus != null) {
        setState(() => _searchStatus = null);
      } else {
        setState(() {});
      }
    } on SocialApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode >= 400 && error.statusCode < 500) {
        await _stopWithError(UserSafeError.message(context, error));
        return;
      }
      setState(() {
        _searchStatus = context.tr('connection_interrupted_retrying');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _searchStatus = context.tr('connection_interrupted_retrying');
        });
      }
    } finally {
      _polling = false;
      if (_searching && !_cancelling) _scheduleNextPoll();
    }
  }

  Future<void> _stopWithError(String message) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!mounted) return;
    setState(() {
      _searching = false;
      _polling = false;
      _cancelling = false;
      _pollAttempt = 0;
    });
    final retry = await GameModal.error(
      context,
      title: context.tr('online_duel'),
      message: message,
      retryLabel: context.tr('retry'),
      cancelLabel: context.tr('cancel'),
    );
    if (retry && mounted) unawaited(_findOpponent());
  }

  Future<void> _cancelSearch() async {
    if (_cancelling || !_searching || _openingRoom) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    final pending = _activeQueueRequest;
    setState(() {
      _cancelling = true;
      _searchStatus = null;
    });

    VariantMatchmakingResult? lateResult;
    try {
      await _matchmaking.cancelRankedQueue();
    } catch (_) {
      // A second cleanup attempt follows after any in-flight join completes.
    }

    if (pending != null) {
      try {
        lateResult = await pending;
      } catch (_) {
        lateResult = null;
      }
    }
    if (!mounted || _openingRoom) return;
    if (lateResult?.matched == true) {
      _cancelling = false;
      _openMatchedResult(lateResult!);
      return;
    }

    try {
      // If the first DELETE raced a POST that re-created our queue row,
      // clean it again after that POST has completed.
      await _matchmaking.cancelRankedQueue();
    } catch (_) {
      // Returning to the selection screen must remain possible while offline.
    }

    try {
      // Another player's coordinator may have claimed our queue entry just
      // before DELETE. Recover that funded room instead of abandoning it.
      final active = await SocialApiClient.instance.activeMatch();
      final roomId = active?['roomId']?.toString().trim() ?? '';
      if (roomId.isNotEmpty && mounted) {
        _cancelling = false;
        _openRecoveredRoom(roomId);
        return;
      }
    } catch (_) {
      // Offline cancellation still returns to the selection screen.
    }

    if (!mounted || _openingRoom) return;
    setState(() {
      _searching = false;
      _polling = false;
      _cancelling = false;
      _searchStatus = null;
      _pollAttempt = 0;
      _activeQueueRequest = null;
    });
  }

  void _openRecoveredRoom(String roomId) {
    if (_variant.id == SudokuVariantId.classic16 &&
        !roomId.startsWith('classic16:')) {
      unawaited(_stopWithError(context.tr('matchmaking_start_failed')));
      return;
    }
    if (_variant.id == SudokuVariantId.classic9 &&
        roomId.startsWith('classic16:')) {
      unawaited(_stopWithError(context.tr('matchmaking_start_failed')));
      return;
    }
    _openOnlineRoom(roomId);
  }

  void _openOnlineRoom(String roomId) {
    if (_openingRoom || !mounted) return;
    _openingRoom = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() {
      _searching = false;
      _polling = false;
      _cancelling = false;
      _searchStatus = null;
    });
    final initialPlayer = _currentVisualPlayer(context);
    Navigator.of(context)
        .push<String>(
          PageRouteBuilder<String>(
            transitionDuration: const Duration(milliseconds: 180),
            reverseTransitionDuration: const Duration(milliseconds: 160),
            pageBuilder: (_, _, _) => PreMatchReadyScreen(
              roomId: roomId,
              initialCurrentPlayer: initialPlayer,
            ),
            transitionsBuilder: (_, animation, _, child) => FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: child,
            ),
          ),
        )
        .then((action) {
          unawaited(_economy.refresh(showLoading: false));
          if (!mounted) return;
          _openingRoom = false;
          if (action == 'new_match') {
            unawaited(_findOpponent());
          } else if (action == 'menu') {
            Navigator.of(context).pop();
          } else {
            setState(() {});
          }
        });
  }
}

@visibleForTesting
Duration matchmakingFallbackDelay(int attempt) {
  if (attempt <= 0) return const Duration(seconds: 3);
  if (attempt <= 4) return const Duration(seconds: 5);
  return const Duration(seconds: 10);
}

class _Header extends StatelessWidget {
  const _Header({
    required this.balance,
    required this.onBack,
    required this.onStore,
  });

  final int balance;
  final VoidCallback onBack;
  final VoidCallback onStore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: onBack,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: onStore,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const DuelAssetIcon(DuelAsset.coin, size: 26),
            label: Text(
              NumberFormat.compact().format(balance),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .9),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: .11)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final SudokuVariant variant;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final is16 = variant.id == SudokuVariantId.classic16;
    final accent = is16 ? const Color(0xFF35D2FF) : const Color(0xFFFFC73D);
    return Semantics(
      selected: selected,
      button: true,
      label: variant.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 7 : 9,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: .15)
                  : const Color(0xFF07111E),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? accent
                    : Colors.white.withValues(alpha: .09),
                width: selected ? 1.7 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: compact ? 42 : 48,
                  height: compact ? 42 : 48,
                  child: Center(
                    child: DuelAssetIcon(
                      is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                      size: compact ? 38 : 44,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        variant.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: const StrutStyle(
                          forceStrutHeight: true,
                          height: 1.05,
                        ),
                        style: TextStyle(
                          color: selected ? accent : Colors.white,
                          fontSize: compact ? 13 : 15,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        is16 ? '1–16' : '1–9',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .55),
                          fontSize: 10,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 19,
                  child: selected
                      ? Icon(Icons.check_rounded, color: accent, size: 18)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryBar extends StatelessWidget {
  const _EntryBar({
    required this.fee,
    required this.pot,
    required this.variant,
  });

  final int fee;
  final int pot;
  final SudokuVariant variant;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFC73D).withValues(alpha: .10),
            const Color(0xFF102235),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF29D398).withValues(alpha: .32),
        ),
      ),
      child: Row(
        children: [
          const DuelAssetIcon(DuelAsset.coin, size: 40),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _EntryValue(
                    label: context.tr('entry_fee'),
                    value: context.tr('coin_amount', <Object>[fee]),
                    color: const Color(0xFFFFC73D),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white.withValues(alpha: .38),
                    size: 18,
                  ),
                ),
                Expanded(
                  child: _EntryValue(
                    label: context.tr('winner_pot'),
                    value: context.tr('coin_amount', <Object>[pot]),
                    color: const Color(0xFF29D398),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF07111E).withValues(alpha: .62),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              variant.label,
              style: const TextStyle(
                color: Color(0xFF35D2FF),
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryValue extends StatelessWidget {
  const _EntryValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .54),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
