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
  static const Duration _queueRefreshInterval = Duration(seconds: 45);

  final EconomyService _economy = EconomyService.instance;
  final VariantMatchmakingClient _matchmaking = VariantMatchmakingClient.instance;

  late SudokuDifficulty _difficulty;
  late SudokuVariant _variant;
  bool _searching = false;
  bool _polling = false;
  Timer? _pollTimer;
  int _pollAttempt = 0;
  DateTime? _lastQueueRefresh;
  String? _searchStatus;

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
    _economy.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_searching) {
      return _SearchingStage(
        variant: _variant,
        difficulty: _difficulty,
        status: _searchStatus,
        onCancel: _cancelSearch,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final horizontal = constraints.maxWidth >= 760;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      compact ? 6 : 10,
                      16,
                      compact ? 10 : 18,
                    ),
                    child: Column(
                      children: [
                        _Header(
                          balance: _economy.balance,
                          onBack: () => Navigator.of(context).pop(),
                          onStore: _openStore,
                        ),
                        SizedBox(height: compact ? 8 : 14),
                        Text(
                          context.tr('online_duel'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 24 : 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                          ),
                        ),
                        SizedBox(height: compact ? 3 : 6),
                        Text(
                          context.tr('same_difficulty_match'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .66),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: compact ? 10 : 18),
                        Expanded(
                          child: horizontal
                              ? Row(
                                  children: [
                                    Expanded(child: _buildVariantPanel(compact)),
                                    const SizedBox(width: 14),
                                    Expanded(child: _buildDifficultyPanel(compact)),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: _buildVariantPanel(compact),
                                    ),
                                    SizedBox(height: compact ? 8 : 12),
                                    Expanded(
                                      flex: 4,
                                      child: _buildDifficultyPanel(compact),
                                    ),
                                  ],
                                ),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        _EntryBar(
                          fee: _entryFee,
                          pot: _economy.winnerPotForDifficulty(_difficulty.name),
                          variant: _variant,
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openLocalPractice,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: Size(0, compact ? 48 : 54),
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: .28),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                icon: const Icon(Icons.sports_esports_rounded),
                                label: Text(context.tr('local_practice')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: _economy.loading
                                    ? null
                                    : _canEnter
                                    ? _findOpponent
                                    : _showInsufficientCoins,
                                style: FilledButton.styleFrom(
                                  minimumSize: Size(0, compact ? 48 : 54),
                                  backgroundColor: _canEnter
                                      ? const Color(0xFF29D398)
                                      : const Color(0xFFFFC73D),
                                  foregroundColor: const Color(0xFF07111E),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                icon: Icon(
                                  _canEnter
                                      ? Icons.travel_explore_rounded
                                      : Icons.lock_rounded,
                                ),
                                label: Text(
                                  _canEnter
                                      ? context.tr('find_opponent')
                                      : context.tr('open_coin_store'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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

  Widget _buildVariantPanel(bool compact) {
    return _Panel(
      title: 'Sudoku',
      child: Row(
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
            if (variant != SudokuVariant.values.last)
              SizedBox(width: compact ? 8 : 12),
          ],
        ],
      ),
    );
  }

  Widget _buildDifficultyPanel(bool compact) {
    return _Panel(
      title: context.tr('choose_duel_difficulty'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final buttonWidth = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: compact ? 6 : 8,
            children: [
              for (final difficulty in SudokuDifficulty.values)
                SizedBox(
                  width: buttonWidth,
                  height: compact ? 38 : 44,
                  child: ChoiceChip(
                    selected: _difficulty == difficulty,
                    onSelected: (_) => setState(() => _difficulty = difficulty),
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
                    selectedColor: const Color(0xFF29D398),
                    backgroundColor: const Color(0xFF122234),
                    labelStyle: TextStyle(
                      color: _difficulty == difficulty
                          ? const Color(0xFF07111E)
                          : Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                    side: BorderSide(
                      color: _difficulty == difficulty
                          ? const Color(0xFF29D398)
                          : Colors.white.withValues(alpha: .16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
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
          showNextAction: false,
          onCompleted:
              ({required seconds, required mistakes, required hints}) =>
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

  Future<void> _findOpponent() async {
    if (_searching) return;
    await _economy.refresh();
    if (!mounted) return;
    if (!_canEnter) {
      await _showInsufficientCoins();
      return;
    }

    setState(() {
      _searching = true;
      _searchStatus = null;
      _lastQueueRefresh = null;
    });

    try {
      await FirebaseSessionService.ensureAnonymousSession();
      final result = await _matchmaking.joinRankedQueue(
        difficulty: _difficulty.name,
        variant: _variant,
      );
      if (!mounted) return;
      if (result.matched) {
        _openOnlineRoom(result.roomId!);
        return;
      }
      if (result.status != 'queued') {
        throw const SocialApiException(0, 'Unexpected matchmaking response.');
      }
      _lastQueueRefresh = DateTime.now();
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

  void _startPolling() {
    _pollTimer?.cancel();
    _pollAttempt = 0;
    unawaited(_pollForMatch());
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    if (!_searching || !mounted) return;
    final delay = matchmakingFallbackDelay(_pollAttempt++);
    _pollTimer = Timer(delay, () => unawaited(_pollForMatch()));
  }

  Future<void> _pollForMatch() async {
    if (!_searching || _polling) return;
    _polling = true;
    try {
      final now = DateTime.now();
      final refreshDue =
          _lastQueueRefresh == null ||
          now.difference(_lastQueueRefresh!) >= _queueRefreshInterval;
      if (refreshDue) {
        final refreshed = await _matchmaking.joinRankedQueue(
          difficulty: _difficulty.name,
          variant: _variant,
        );
        _lastQueueRefresh = now;
        if (!mounted) return;
        if (refreshed.matched) {
          _openOnlineRoom(refreshed.roomId!);
          return;
        }
      }
      final active = await SocialApiClient.instance.activeMatch();
      final roomId = active?['roomId']?.toString();
      if (!mounted || roomId == null || roomId.isEmpty) return;
      _openOnlineRoom(roomId);
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
      _scheduleNextPoll();
    }
  }

  Future<void> _stopWithError(String message) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!mounted) return;
    setState(() {
      _searching = false;
      _polling = false;
      _lastQueueRefresh = null;
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
    _pollTimer?.cancel();
    _pollTimer = null;
    if (mounted) {
      setState(() {
        _searching = false;
        _polling = false;
        _searchStatus = null;
        _lastQueueRefresh = null;
        _pollAttempt = 0;
      });
    }
    try {
      await _matchmaking.cancelRankedQueue();
    } catch (_) {
      // Returning to the menu must remain possible while offline.
    }
  }

  void _openOnlineRoom(String roomId) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (mounted) {
      setState(() {
        _searching = false;
        _polling = false;
        _searchStatus = null;
      });
    }
    Navigator.of(context)
        .push<String>(
          MaterialPageRoute(
            builder: (_) => PreMatchReadyScreen(roomId: roomId),
          ),
        )
        .then((action) {
          unawaited(_economy.refresh(showLoading: false));
          if (!mounted) return;
          if (action == 'new_match') {
            unawaited(_findOpponent());
          } else if (action == 'menu') {
            Navigator.of(context).pop();
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
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: onBack,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const Spacer(),
        FilledButton.tonalIcon(
          onPressed: onStore,
          icon: const DuelAssetIcon(DuelAsset.coin, size: 18),
          label: Text(NumberFormat.compact().format(balance)),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
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
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: .16)
                  : const Color(0xFF07111E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? accent : Colors.white.withValues(alpha: .10),
                width: selected ? 2 : 1,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 8 : 11),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: DuelAssetIcon(
                      is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                      size: compact ? 84 : 112,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    variant.label,
                    style: TextStyle(
                      color: selected ? accent : Colors.white,
                      fontSize: compact ? 17 : 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    is16 ? '1–16' : '1–9',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .58),
                      fontWeight: FontWeight.w700,
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF102235),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF29D398).withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          const DuelAssetIcon(DuelAsset.coin, size: 20),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '$fee → $pot',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            variant.label,
            style: const TextStyle(
              color: Color(0xFF29D398),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchingStage extends StatelessWidget {
  const _SearchingStage({
    required this.variant,
    required this.difficulty,
    required this.status,
    required this.onCancel,
  });

  final SudokuVariant variant;
  final SudokuDifficulty difficulty;
  final String? status;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final is16 = variant.id == SudokuVariantId.classic16;
    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton.filledTonal(
                    onPressed: onCancel,
                    tooltip: context.tr('cancel_search'),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .92, end: 1.04),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: DuelAssetIcon(
                    is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                    size: 174,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  context.tr('finding_opponent_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${variant.label} · ${context.strings.difficultyLabel(difficulty)}',
                  style: const TextStyle(
                    color: Color(0xFF29D398),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  status ?? context.tr('searching_similar_opponents'),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .65),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(strokeWidth: 4),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: Text(context.tr('cancel_search')),
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
