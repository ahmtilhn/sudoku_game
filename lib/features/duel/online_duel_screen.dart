import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../models/rank_identity_models.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_emote_hub.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../services/rank_identity_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/sudoku_board.dart';
import '../economy/coin_store_screen.dart';
import 'matchmaking_screen.dart';
import 'pre_match_ready_screen.dart';

class OnlineDuelScreen extends StatefulWidget {
  const OnlineDuelScreen({super.key, required this.roomId, this.controller});

  final String roomId;
  final OnlineDuelController? controller;

  @override
  State<OnlineDuelScreen> createState() => _OnlineDuelScreenState();
}

class _OnlineDuelScreenState extends State<OnlineDuelScreen> {
  OnlineDuelController? _controller;
  StreamSubscription<OnlineDuelSnapshot>? _subscription;
  StreamSubscription<OnlineDuelFeedback>? _feedbackSubscription;
  OnlineDuelSnapshot? _snapshot;
  Object? _error;
  int? _selectedIndex;
  int? _feedbackCell;
  final Set<int> _localMoveIndexes = <int>{};
  final Set<int> _opponentMoveIndexes = <int>{};
  bool _loading = true;
  bool _screenLoadedSent = false;
  Timer? _feedbackTimer;
  Timer? _progressTimer;
  Timer? _resultSettlementTimer;
  Timer? _disconnectEscapeTimer;
  Timer? _turnNoticeTimer;
  String? _shownResultFor;
  String? _settlementWaitMatchId;
  OnlineDuelSeat? _turnNoticeSeat;
  int _resultSettlementAttempts = 0;
  bool _forfeiting = false;
  bool _localConnectionInterrupted = false;
  bool _turnNoticeVisible = false;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    unawaited(_controller?.dispose());
    _feedbackTimer?.cancel();
    _progressTimer?.cancel();
    _resultSettlementTimer?.cancel();
    _disconnectEscapeTimer?.cancel();
    _turnNoticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final controller =
          widget.controller ??
          OnlineDuelController(
            await WebSocketOnlineDuelTransport.connect(widget.roomId),
          );
      controller.start();
      final subscription = controller.snapshots.listen((snapshot) {
        if (!mounted) return;
        final previous = _snapshot;
        final previousLocalTurn = _snapshot?.isLocalTurn ?? false;
        if (previous != null && previous.matchId != snapshot.matchId) {
          _resultSettlementTimer?.cancel();
          _resultSettlementTimer = null;
          _settlementWaitMatchId = null;
          _resultSettlementAttempts = 0;
          _shownResultFor = null;
        }
        _markProgress(previous, snapshot);
        setState(() {
          _snapshot = snapshot;
          _loading = false;
          _error = null;
          if (!snapshot.isLocalTurn) _selectedIndex = null;
          if (snapshot.isFinished) _forfeiting = false;
        });
        _syncTurnNotice(previous, snapshot);
        _syncDisconnectEscape(snapshot);
        if (!previousLocalTurn && snapshot.isLocalTurn) {
          unawaited(HapticFeedback.mediumImpact());
        }
        _sendScreenLoadedAfterRender(snapshot);
        _showResultOnce(snapshot);
      });
      final feedbackSubscription = controller.feedback.listen((feedback) {
        if (!mounted) return;

        _feedbackTimer?.cancel();
        setState(() {
          if (feedback.accepted) {
            _selectedIndex = null;
            _feedbackCell = null;
            if (feedback.cellIndex != null) {
              _localMoveIndexes
                ..clear()
                ..add(feedback.cellIndex!);
              _opponentMoveIndexes.clear();
            }
          } else {
            _feedbackCell = feedback.cellIndex;
          }
        });

        if (!feedback.accepted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Text(feedback.message),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        if (_feedbackCell != null) {
          _feedbackTimer = Timer(const Duration(milliseconds: 650), () {
            if (mounted) setState(() => _feedbackCell = null);
          });
        }
        _scheduleProgressClear();
      });
      setState(() {
        _controller = controller;
        _subscription = subscription;
        _feedbackSubscription = feedbackSubscription;
      });
      controller.requestSnapshot();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _syncTurnNotice(
    OnlineDuelSnapshot? previous,
    OnlineDuelSnapshot snapshot,
  ) {
    if (snapshot.status != OnlineDuelStatus.active || snapshot.isFinished) {
      _turnNoticeTimer?.cancel();
      _turnNoticeTimer = null;
      if (_turnNoticeVisible) {
        setState(() => _turnNoticeVisible = false);
      }
      return;
    }

    final changed =
        previous?.status != OnlineDuelStatus.active ||
        previous?.currentTurnSeat != snapshot.currentTurnSeat;
    if (!changed) return;

    _turnNoticeTimer?.cancel();
    setState(() {
      _turnNoticeSeat = snapshot.currentTurnSeat;
      _turnNoticeVisible = true;
    });
    _turnNoticeTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _turnNoticeVisible = false);
    });
  }

  Future<void> _requestForfeit() async {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.isFinished || _forfeiting || !mounted) {
      return;
    }
    final forfeit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('online_forfeit_title')),
        content: Text(context.tr('online_forfeit_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('stay')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('forfeit_and_leave')),
          ),
        ],
      ),
    );
    if (forfeit != true || !mounted) return;
    await _submitForfeitAndWaitForResult();
  }

  Future<void> _submitForfeitAndWaitForResult() async {
    setState(() => _forfeiting = true);
    _controller?.forfeit();
    _controller?.requestSnapshot();
    final settled = await waitForAuthoritativeResult();
    if (!mounted) return;
    if (!settled) {
      setState(() => _forfeiting = false);
      _controller?.requestSnapshot();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('connection_interrupted_retrying'))),
      );
      return;
    }
    final finished = _snapshot;
    if (finished != null) {
      _showResultOnce(finished);
    }
  }

  Future<bool> waitForAuthoritativeResult() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (_snapshot?.isFinished == true) return true;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _controller?.requestSnapshot();
    }
    return _snapshot?.isFinished == true;
  }

  void _syncDisconnectEscape(OnlineDuelSnapshot snapshot) {
    if (snapshot.status == OnlineDuelStatus.paused && !snapshot.isFinished) {
      _localConnectionInterrupted = true;
      _disconnectEscapeTimer ??= Timer(const Duration(seconds: 30), () {
        if (!mounted || _snapshot?.isFinished == true) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return;
    }

    _localConnectionInterrupted = false;
    _disconnectEscapeTimer?.cancel();
    _disconnectEscapeTimer = null;
  }

  void _selectCell(int index) {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.isFinished) return;
    if (snapshot.puzzle[index] != 0 ||
        snapshot.board[index] != 0 ||
        _controller?.pendingMove == true) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _enterNumber(int value) {
    final snapshot = _snapshot;
    final index = _selectedIndex;
    if (snapshot == null || index == null) return;
    _controller?.move(index, value);
  }

  void _markProgress(
    OnlineDuelSnapshot? previous,
    OnlineDuelSnapshot snapshot,
  ) {
    if (previous == null || previous.matchId != snapshot.matchId) return;
    final changed = <int>{};
    final max = previous.board.length < snapshot.board.length
        ? previous.board.length
        : snapshot.board.length;
    for (var index = 0; index < max; index++) {
      if (previous.board[index] == 0 && snapshot.board[index] != 0) {
        changed.add(index);
      }
    }
    if (changed.isEmpty) return;
    final localChanged = _localMoveIndexes.any(changed.contains);
    if (!localChanged) {
      _opponentMoveIndexes
        ..clear()
        ..addAll(changed);
    }
    _scheduleProgressClear();
  }

  void _scheduleProgressClear() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _localMoveIndexes.clear();
        _opponentMoveIndexes.clear();
      });
    });
  }

  void _sendScreenLoadedAfterRender(OnlineDuelSnapshot snapshot) {
    if (_screenLoadedSent ||
        snapshot.status == OnlineDuelStatus.active ||
        snapshot.isFinished) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _screenLoadedSent) return;
      _screenLoadedSent = true;
      _controller?.screenLoaded();
    });
  }

  void _showResultOnce(OnlineDuelSnapshot snapshot) {
    if (!snapshot.isFinished || _shownResultFor == snapshot.matchId) return;
    if (_settlementWaitMatchId != snapshot.matchId) {
      _resultSettlementTimer?.cancel();
      _resultSettlementTimer = null;
      _settlementWaitMatchId = snapshot.matchId;
      _resultSettlementAttempts = 0;
    }
    final needsSettlement =
        (snapshot.status == OnlineDuelStatus.completed ||
            snapshot.status == OnlineDuelStatus.forfeited) &&
        snapshot.rating == null;
    if (needsSettlement && _resultSettlementAttempts < 20) {
      if (_resultSettlementTimer == null) {
        _resultSettlementAttempts++;
        _resultSettlementTimer = Timer(const Duration(milliseconds: 400), () {
          _resultSettlementTimer = null;
          _controller?.requestSnapshot();
        });
      }
      return;
    }
    _resultSettlementTimer?.cancel();
    _resultSettlementTimer = null;
    _shownResultFor = snapshot.matchId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(
        EconomyService.instance.refresh(showLoading: false).catchError((
          Object error,
        ) {
          debugPrint('Result economy refresh unavailable: $error');
        }),
      );
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .56),
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (sheetContext) => _OnlineResultSheet(snapshot: snapshot),
      );
      if (!mounted || action == null) return;
      if (action.startsWith('rematch:')) {
        final roomId = action.substring('rematch:'.length);
        await _handoffToRematch(roomId);
      } else if (action == 'new_match') {
        await Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
          (route) => route.isFirst,
        );
      } else if (action == 'menu') {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  Future<void> _handoffToRematch(String roomId) async {
    _resultSettlementTimer?.cancel();
    _resultSettlementTimer = null;
    await _subscription?.cancel();
    await _feedbackSubscription?.cancel();
    await _controller?.dispose();
    _subscription = null;
    _feedbackSubscription = null;
    _controller = null;
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final activeArena = snapshot?.status == OnlineDuelStatus.active;
    final inputLocked =
        snapshot != null &&
        (snapshot.isFinished ||
            !snapshot.isLocalTurn ||
            _controller?.pendingMove == true);

    return PopScope(
      canPop: snapshot?.isFinished ?? true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestForfeit());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07111E),
        bottomNavigationBar: snapshot == null
            ? null
            : Theme(
                data: activeArena ? _arenaTheme(context) : Theme.of(context),
                child: NumberPadDock(
                  compact: true,
                  child: NumberPad(
                    maxValue: snapshot.boardSize,
                    completedValues: completedSudokuNumbers(
                      board: snapshot.board,
                      maxValue: snapshot.boardSize,
                    ),
                    enabled: !inputLocked,
                    onNumber: _enterNumber,
                    onErase: () => setState(() => _selectedIndex = null),
                    showErase: false,
                  ),
                ),
              ),
        body: Theme(
          data: activeArena ? _arenaTheme(context) : Theme.of(context),
          child: AppBackdrop(
            dim: activeArena ? .34 : .42,
            child: SafeArea(child: _buildBody(context)),
          ),
        ),
      ),
    );
  }

  ThemeData _arenaTheme(BuildContext context) {
    final base = Theme.of(context);
    const scheme = ColorScheme.dark(
      primary: Color(0xFF29D398),
      onPrimary: Color(0xFF08110E),
      secondary: Color(0xFF3AA9FF),
      onSecondary: Color(0xFF071B2E),
      tertiary: Color(0xFFFFC94D),
      onTertiary: Color(0xFF2B1F00),
      surface: Color(0xFF132026),
      surfaceContainerLow: Color(0xFF121B20),
      surfaceContainer: Color(0xFF18242B),
      surfaceContainerHigh: Color(0xFF22313A),
      surfaceContainerHighest: Color(0xFF22313A),
      outline: Color(0xFF7F8B94),
      outlineVariant: Color(0xFF2E414B),
      error: Color(0xFFFF5B6B),
      errorContainer: Color(0xFF3A151D),
      onSurface: Color(0xFFF8FAFC),
      onSurfaceVariant: Color(0xFFB7C3CA),
    );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF07111E),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: InPageHeader(title: context.tr('online_duel')),
          ),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (_error != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: InPageHeader(title: context.tr('online_duel')),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const DuelAssetIcon(DuelAsset.cloud, size: 44),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('online_connection_failed', <Object>[
                        UserSafeError.message(context, _error!),
                      ]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        unawaited(_connect());
                      },
                      icon: const DuelAssetIcon(DuelAsset.refresh, size: 22),
                      label: Text(context.tr('refresh')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(child: Text(context.tr('online_waiting_snapshot')));
    }

    final puzzle = SudokuPuzzle(
      id: 'online-${snapshot.matchId}',
      title: context.tr('online_duel'),
      difficulty: _difficulty(snapshot.difficulty),
      puzzle: snapshot.puzzle,
      solution: List<int>.filled(snapshot.cellCount, 1),
      size: snapshot.boardSize,
      boxRows: snapshot.boardSize == 16 ? 4 : 3,
      boxColumns: snapshot.boardSize == 16 ? 4 : 3,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 720 || constraints.maxWidth <= 520;
        final board = RepaintBoundary(
          child: IgnorePointer(
            ignoring: snapshot.isFinished || !snapshot.isLocalTurn,
            child: SudokuBoard(
              puzzle: puzzle,
              board: snapshot.board,
              selectedIndex: _selectedIndex,
              errorIndex: _feedbackCell,
              localMoveIndexes: _localMoveIndexes,
              opponentMoveIndexes: _opponentMoveIndexes,
              enabled: !snapshot.isFinished && snapshot.isLocalTurn,
              onCellTap: _selectCell,
            ),
          ),
        );

        if (snapshot.status == OnlineDuelStatus.active) {
          return _ArenaMatchLayout(
            snapshot: snapshot,
            compact: compact,
            board: board,
            sendingMove: _controller?.pendingMove == true,
            onForfeit: _requestForfeit,
            forfeiting: _forfeiting,
            turnNoticeVisible: _turnNoticeVisible,
            turnNoticeLocal:
                (_turnNoticeSeat ?? snapshot.currentTurnSeat) ==
                snapshot.youSeat,
          );
        }

        return _ConnectingMatchLayout(
          snapshot: snapshot,
          compact: compact,
          board: board,
          locallyInterrupted: _localConnectionInterrupted,
        );
      },
    );
  }

  SudokuDifficulty _difficulty(String value) {
    return SudokuDifficulty.values.firstWhere(
      (difficulty) => difficulty.name == value,
      orElse: () => SudokuDifficulty.easy,
    );
  }
}

class _ConnectingMatchLayout extends StatelessWidget {
  const _ConnectingMatchLayout({
    required this.snapshot,
    required this.compact,
    required this.board,
    required this.locallyInterrupted,
  });

  final OnlineDuelSnapshot snapshot;
  final bool compact;
  final Widget board;
  final bool locallyInterrupted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 5 : 8,
        compact ? 4 : 7,
        compact ? 5 : 8,
        compact ? 5 : 8,
      ),
      child: Column(
        children: [
          _MatchHeader(snapshot: snapshot, compact: compact),
          SizedBox(height: compact ? 14 : 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                locallyInterrupted
                    ? context.tr('reconnecting')
                    : context.tr('opponent_connecting'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: locallyInterrupted
                      ? const Color(0xFFFFC94D)
                      : const Color(0xFF8ED8FF),
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: locallyInterrupted
                      ? const Color(0xFFFFC94D)
                      : const Color(0xFF29D398),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 18 : 26),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = mathMin(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ).clamp(280.0, 720.0);
                  return SizedBox.square(
                    dimension: size,
                    child: Opacity(
                      opacity: .82,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: board,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  double mathMin(double a, double b) => a < b ? a : b;
}

class _OnlineResultSheet extends StatefulWidget {
  const _OnlineResultSheet({required this.snapshot});

  final OnlineDuelSnapshot snapshot;

  @override
  State<_OnlineResultSheet> createState() => _OnlineResultSheetState();
}

class _OnlineResultSheetState extends State<_OnlineResultSheet> {
  final EconomyService _economy = EconomyService.instance;
  Timer? _pollTimer;
  Timer? _clockTimer;
  RematchInvitation? _invitation;
  RankMatchResult? _rankResult;
  bool _rankLoading = true;
  bool _busy = false;
  bool _openingAcceptedRoom = false;
  String? _statusMessage;
  String? _friendshipStatus;

  OnlineDuelSnapshot get snapshot => widget.snapshot;

  OnlineDuelSeat get opponentSeat => snapshot.youSeat == OnlineDuelSeat.a
      ? OnlineDuelSeat.b
      : OnlineDuelSeat.a;

  OnlineDuelPlayer get opponent => snapshot.players[opponentSeat]!;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_onEconomyChanged);
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => unawaited(_pollRematches()),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_pollRematches());
    unawaited(_loadFriendshipStatus());
    unawaited(_loadRankResult());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRankResult() async {
    if (snapshot.mode != 'ranked') {
      if (mounted) setState(() => _rankLoading = false);
      return;
    }
    try {
      final result = await RankIdentityService.instance.loadMatchResult(
        snapshot.matchId,
      );
      if (!mounted) return;
      setState(() => _rankResult = result);
      if (result.settled) {
        try {
          await RankIdentityService.instance.refresh();
          await _economy.refresh(showLoading: false);
        } catch (error) {
          debugPrint('Rank profile refresh unavailable: $error');
        }
      }
    } catch (error) {
      debugPrint('Rank result unavailable: $error');
    } finally {
      if (mounted) setState(() => _rankLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localScore = snapshot.scores[snapshot.youSeat] ?? 0;
    final opponentScore = snapshot.scores[opponentSeat] ?? 0;
    final won = snapshot.winnerSeat == snapshot.youSeat;
    final draw = snapshot.winnerSeat == null;
    final entryFee = _economy.entryFeeForDifficulty(snapshot.difficulty);
    final resultTitle = draw
        ? context.tr('draw')
        : won
        ? context.tr('you_won')
        : context.tr('you_lost');
    final resultSubtitle = draw
        ? context.tr('result_draw_subtitle')
        : won
        ? context.tr('result_win_subtitle')
        : context.tr('result_loss_subtitle');
    final you = snapshot.players[snapshot.youSeat]!;
    final canPlay = _economy.balance >= entryFee;
    final invite = _invitation;
    final seconds = invite == null
        ? 0
        : invite.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 10);
    final localNetCoin = draw
        ? 0
        : won
        ? entryFee
        : -entryFee;
    final opponentNetCoin = -localNetCoin;
    String coinLabel(int value) =>
        '${value > 0 ? '+' : ''}${context.tr('coin_amount', <Object>[value])}';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _ResultCard(
        title: resultTitle,
        subtitle: resultSubtitle,
        won: won,
        draw: draw,
        localPlayer: you,
        opponent: opponent,
        localScore: localScore,
        opponentScore: opponentScore,
        metrics: [
          _ResultMetric(
            label: context.tr('correct_moves'),
            localValue: '${snapshot.correctMoves[snapshot.youSeat] ?? 0}',
            opponentValue: '${snapshot.correctMoves[opponentSeat] ?? 0}',
            icon: Icons.check_rounded,
          ),
          _ResultMetric(
            label: context.tr('mistakes'),
            localValue: '${snapshot.mistakes[snapshot.youSeat] ?? 0}',
            opponentValue: '${snapshot.mistakes[opponentSeat] ?? 0}',
            icon: Icons.close_rounded,
          ),
          _ResultMetric(
            label: context.tr('timeouts'),
            localValue: '${snapshot.timeouts[snapshot.youSeat] ?? 0}',
            opponentValue: '${snapshot.timeouts[opponentSeat] ?? 0}',
            icon: Icons.timer_outlined,
          ),
          _ResultMetric(
            label: context.tr('hints'),
            localValue: context.tr('not_available_short'),
            opponentValue: context.tr('not_available_short'),
            icon: Icons.lightbulb_outline_rounded,
          ),
          _ResultMetric(
            label: context.tr('coin_result'),
            localValue: coinLabel(localNetCoin),
            opponentValue: coinLabel(opponentNetCoin),
            icon: Icons.monetization_on_outlined,
          ),
        ],
        rankResult: _rankResult,
        rankLoading: _rankLoading && snapshot.mode == 'ranked',
        showRank: snapshot.mode == 'ranked',
        statusMessage: _statusMessage,
        invitation: invite,
        invitationSeconds: seconds,
        canPlay: canPlay,
        busy: _busy,
        onInvitationDecline: invite == null ? null : () => _respond(invite, false),
        onInvitationAccept: invite == null ? null : () => _respond(invite, true),
        onNewMatch: () => Navigator.of(context).pop('new_match'),
        onRematch: _createRematch,
        onAddFriend: _canAddFriend ? _addFriend : null,
        onMenu: () => Navigator.of(context).pop('menu'),
      ),
    );
  }

  Future<void> _createRematch() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final invitation = await _economy.createRematch(snapshot.matchId);
      if (!mounted) return;
      setState(() {
        _invitation = invitation;
        _statusMessage = context.tr('rematch_invitation_sent');
      });
    } on EconomyApiException catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(RematchInvitation invitation, bool accept) async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final updated = await _economy.respondRematch(
        invitationId: invitation.id,
        accept: accept,
      );
      if (!mounted) return;
      setState(() => _invitation = updated);
      if (accept && updated.roomId?.isNotEmpty == true) {
        await _openAcceptedRoom(updated.roomId!);
      } else if (accept) {
        setState(() => _statusMessage = context.tr('rematch_waiting_room'));
        final opened = await _waitForAcceptedRematch(invitation.id);
        if (!opened && mounted) {
          setState(() => _statusMessage = context.tr('rematch_could_not_start'));
        }
      } else {
        setState(() => _statusMessage = context.tr('rematch_declined'));
      }
    } on EconomyApiException catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _waitForAcceptedRematch(String invitationId) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return false;
      try {
        final invitations = await _economy.loadRematches();
        if (!mounted) return false;
        for (final item in invitations) {
          if (item.id != invitationId) continue;
          setState(() => _invitation = item);
          if (item.status == 'accepted' && item.roomId?.isNotEmpty == true) {
            await _openAcceptedRoom(item.roomId!);
            return true;
          }
          if (item.status == 'declined' || item.status == 'expired') {
            return false;
          }
        }
      } catch (_) {
        // Keep the accept path alive while the backend settles the rematch room.
      }
    }
    return false;
  }

  Future<void> _pollRematches() async {
    try {
      final invitations = await _economy.loadRematches();
      if (!mounted) return;
      RematchInvitation? relevant;
      for (final item in invitations) {
        if (item.previousMatchId == snapshot.matchId) {
          relevant = item;
          break;
        }
      }
      if (relevant == null) return;
      final previousStatus = _invitation?.status;
      setState(() => _invitation = relevant);
      if (relevant.status == 'accepted' && relevant.roomId?.isNotEmpty == true) {
        await _openAcceptedRoom(relevant.roomId!);
      } else if (previousStatus == 'pending' && relevant.status == 'declined') {
        setState(() => _statusMessage = context.tr('challenge_declined'));
      } else if (previousStatus == 'pending' && relevant.status == 'expired') {
        setState(() => _statusMessage = context.tr('challenge_timed_out'));
      } else if (relevant.status == 'insufficient_coins') {
        setState(() => _statusMessage = context.tr('player_not_enough_coin'));
      }
    } catch (_) {
      // Result actions remain usable if a background poll temporarily fails.
    }
  }

  Future<void> _openAcceptedRoom(String roomId) async {
    if (_openingAcceptedRoom) return;
    _openingAcceptedRoom = true;
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop('rematch:$roomId');
  }

  Future<void> _addFriend() async {
    if (!_canAddFriend) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await SocialApiClient.instance.sendFriendRequest(opponent.publicId);
      if (!mounted) return;
      setState(() {
        _friendshipStatus = 'pending';
        _statusMessage = context.tr('friend_request_sent');
      });
    } on SocialApiException catch (error) {
      if (!mounted) return;
      final message = error.message.toLowerCase();
      setState(() {
        if (message.contains('already friends')) {
          _friendshipStatus = 'accepted';
        } else if (message.contains('pending')) {
          _friendshipStatus = 'pending';
        }
        _statusMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canAddFriend =>
      _friendshipStatus != 'accepted' && _friendshipStatus != 'pending';

  Future<void> _loadFriendshipStatus() async {
    try {
      final friends = await SocialApiClient.instance.loadFriends();
      if (!mounted) return;
      if (friends.any((player) => player.publicId == opponent.publicId)) {
        setState(() => _friendshipStatus = 'accepted');
        return;
      }
      final recent = await SocialApiClient.instance.loadRecentOpponents();
      if (!mounted) return;
      for (final player in recent) {
        if (player.publicId == opponent.publicId &&
            player.friendshipStatus != null) {
          setState(() => _friendshipStatus = player.friendshipStatus);
          return;
        }
      }
    } catch (error) {
      debugPrint('Result friendship status unavailable: $error');
    }
  }
}

class _ResultMetric {
  const _ResultMetric({
    required this.label,
    required this.localValue,
    required this.opponentValue,
    required this.icon,
  });

  final String label;
  final String localValue;
  final String opponentValue;
  final IconData icon;
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.title,
    required this.subtitle,
    required this.won,
    required this.draw,
    required this.localPlayer,
    required this.opponent,
    required this.localScore,
    required this.opponentScore,
    required this.metrics,
    required this.rankResult,
    required this.rankLoading,
    required this.showRank,
    required this.statusMessage,
    required this.invitation,
    required this.invitationSeconds,
    required this.canPlay,
    required this.busy,
    required this.onInvitationDecline,
    required this.onInvitationAccept,
    required this.onNewMatch,
    required this.onRematch,
    required this.onAddFriend,
    required this.onMenu,
  });

  final String title;
  final String subtitle;
  final bool won;
  final bool draw;
  final OnlineDuelPlayer localPlayer;
  final OnlineDuelPlayer opponent;
  final int localScore;
  final int opponentScore;
  final List<_ResultMetric> metrics;
  final RankMatchResult? rankResult;
  final bool rankLoading;
  final bool showRank;
  final String? statusMessage;
  final RematchInvitation? invitation;
  final int invitationSeconds;
  final bool canPlay;
  final bool busy;
  final VoidCallback? onInvitationDecline;
  final VoidCallback? onInvitationAccept;
  final VoidCallback onNewMatch;
  final VoidCallback onRematch;
  final VoidCallback? onAddFriend;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final accent = draw
        ? const Color(0xFF8DA2BE)
        : won
        ? const Color(0xFF29D398)
        : const Color(0xFFFF6B62);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF17283B), Color(0xFF101C2B)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: .32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .42),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shield_rounded,
            color: Color(0xFFFFC94D),
            size: 48,
          ),
          const SizedBox(height: 4),
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .76),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _ResultPlayers(
            localPlayer: localPlayer,
            opponent: opponent,
            localScore: localScore,
            opponentScore: opponentScore,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
            ),
            child: Column(
              children: [
                for (final metric in metrics) _ResultMetricRow(metric: metric),
              ],
            ),
          ),
          if (showRank) ...[
            const SizedBox(height: 10),
            _ResultRankPanel(result: rankResult, loading: rankLoading),
          ],
          if (statusMessage != null) ...[
            const SizedBox(height: 9),
            Text(
              statusMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF29D398),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (invitation != null && invitation!.status == 'pending') ...[
            const SizedBox(height: 10),
            _InlineRematch(
              invitation: invitation!,
              seconds: invitationSeconds,
              busy: busy,
              canPlay: canPlay,
              onDecline: onInvitationDecline,
              onAccept: onInvitationAccept,
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: busy || !canPlay ? null : onNewMatch,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                context.tr('find_new_match'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF20A968),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: busy || !canPlay || invitation?.status == 'pending'
                  ? null
                  : onRematch,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                context.tr('challenge_again'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onAddFriend,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text(context.tr('add_friend')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onMenu,
                    icon: const Icon(Icons.home_outlined, size: 18),
                    label: Text(context.tr('main_menu')),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultPlayers extends StatelessWidget {
  const _ResultPlayers({
    required this.localPlayer,
    required this.opponent,
    required this.localScore,
    required this.opponentScore,
  });

  final OnlineDuelPlayer localPlayer;
  final OnlineDuelPlayer opponent;
  final int localScore;
  final int opponentScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF213047),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ResultPlayer(
              player: localPlayer,
              score: localScore,
              accent: const Color(0xFF29D398),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 7),
            child: Text(
              'VS',
              style: TextStyle(
                color: Color(0xFFFFC94D),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: _ResultPlayer(
              player: opponent,
              score: opponentScore,
              accent: const Color(0xFF66C7FF),
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultPlayer extends StatelessWidget {
  const _ResultPlayer({
    required this.player,
    required this.score,
    required this.accent,
    this.alignEnd = false,
  });

  final OnlineDuelPlayer player;
  final int score;
  final Color accent;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 2),
      ),
      child: PlayerAvatar(
        displayName: player.displayName,
        avatarKey: player.avatarKey,
        radius: 18,
        semanticLabel: player.displayName,
      ),
    );
    final info = Expanded(
      child: Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            player.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            player.username.isEmpty ? '' : '@${player.username}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .52),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Row(
      textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
      children: [avatar, const SizedBox(width: 7), info],
    );
  }
}

class _ResultMetricRow extends StatelessWidget {
  const _ResultMetricRow({required this.metric});

  final _ResultMetric metric;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              metric.localValue,
              style: const TextStyle(
                color: Color(0xFF29D398),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(metric.icon, color: const Color(0xFFFFC94D), size: 15),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .78),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              metric.opponentValue,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xFF66C7FF),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRankPanel extends StatelessWidget {
  const _ResultRankPanel({required this.result, required this.loading});

  final RankMatchResult? result;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 46,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final value = result;
    if (value == null || !value.rated || !value.settled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Text(
          'Rank Points will update automatically.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .60),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final afterTier = rankTierForPoints(value.rpAfter);
    final nextIndex = rankTierCatalog.indexWhere((tier) => tier.key == afterTier.key);
    final next = nextIndex >= 0 && nextIndex < rankTierCatalog.length - 1
        ? rankTierCatalog[nextIndex + 1]
        : null;
    final progress = next == null
        ? 1.0
        : ((value.rpAfter - afterTier.minPoints) /
                  (next.minPoints - afterTier.minPoints))
              .clamp(0.0, 1.0)
              .toDouble();
    final deltaColor = value.rpDelta >= 0
        ? const Color(0xFF29D398)
        : const Color(0xFFFF6B62);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF29D398).withValues(alpha: .18)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFC94D), size: 18),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Rank Points',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${value.rpDelta >= 0 ? '+' : ''}${value.rpDelta} RP',
                style: TextStyle(
                  color: deltaColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(
                '${value.rpBefore}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .52),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: .10),
                    valueColor: AlwaysStoppedAnimation<Color>(deltaColor),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '${value.rpAfter} RP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  value.rankAfterName,
                  style: const TextStyle(
                    color: Color(0xFF8ED8FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (next != null)
                Text(
                  '${next.minPoints - value.rpAfter} RP to ${next.label}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .48),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineRematch extends StatelessWidget {
  const _InlineRematch({
    required this.invitation,
    required this.seconds,
    required this.busy,
    required this.canPlay,
    required this.onDecline,
    required this.onAccept,
  });

  final RematchInvitation invitation;
  final int seconds;
  final bool busy;
  final bool canPlay;
  final VoidCallback? onDecline;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    if (invitation.isSender) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('waiting_for_player_seconds', <Object>[
                  invitation.recipient.displayName,
                  seconds,
                ]),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF223047),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF29D398).withValues(alpha: .16)),
      ),
      child: Column(
        children: [
          Text(
            '${invitation.sender.displayName} wants a rematch · ${seconds}s',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  child: Text(context.tr('decline')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy || !canPlay ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF29D398),
                    foregroundColor: const Color(0xFF071612),
                  ),
                  child: Text(
                    context.tr('accept'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TurnAwareBoardFrame extends StatelessWidget {
  const _TurnAwareBoardFrame({required this.snapshot, required this.child});

  final OnlineDuelSnapshot snapshot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (!snapshot.isLocalTurn)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .30),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArenaMatchLayout extends StatelessWidget {
  const _ArenaMatchLayout({
    required this.snapshot,
    required this.compact,
    required this.board,
    required this.sendingMove,
    required this.onForfeit,
    required this.forfeiting,
    required this.turnNoticeVisible,
    required this.turnNoticeLocal,
  });

  final OnlineDuelSnapshot snapshot;
  final bool compact;
  final Widget board;
  final bool sendingMove;
  final VoidCallback onForfeit;
  final bool forfeiting;
  final bool turnNoticeVisible;
  final bool turnNoticeLocal;

  @override
  Widget build(BuildContext context) {
    final hub = OnlineDuelEmoteHub.instance;
    final opponentOnLeft = snapshot.youSeat == OnlineDuelSeat.b;

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 5 : 8,
            compact ? 4 : 7,
            compact ? 5 : 8,
            compact ? 4 : 7,
          ),
          child: Column(
            children: [
              _MatchHeader(snapshot: snapshot, compact: compact),
              SizedBox(height: compact ? 5 : 7),
              _TurnStatusStrip(
                localTurn: snapshot.isLocalTurn,
                sendingMove: sendingMove,
                pulse: turnNoticeVisible,
                pulseLocal: turnNoticeLocal,
                compact: compact,
              ),
              SizedBox(height: compact ? 7 : 9),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boardSize = mathMin(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ).clamp(290.0, 720.0);
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox.square(
                        dimension: boardSize,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: (snapshot.isLocalTurn
                                      ? const Color(0xFF29D398)
                                      : const Color(0xFF66C7FF))
                                  .withValues(alpha: .15),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (snapshot.isLocalTurn
                                        ? const Color(0xFF29D398)
                                        : const Color(0xFF3AA9FF))
                                    .withValues(alpha: .10),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: _TurnAwareBoardFrame(
                            snapshot: snapshot,
                            child: board,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              _ArenaBottomControls(
                hub: hub,
                forfeiting: forfeiting,
                onForfeit: onForfeit,
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: hub,
          builder: (context, _) {
            if (!hub.visible || hub.incomingEmoteId == null) {
              return const SizedBox.shrink();
            }
            return Positioned(
              top: compact ? 76 : 88,
              left: opponentOnLeft ? 12 : null,
              right: opponentOnLeft ? null : 12,
              child: IgnorePointer(
                child: OnlineDuelEmoteBubble(
                  emoteId: hub.incomingEmoteId,
                  accent: const Color(0xFFFFC94D),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  double mathMin(double a, double b) => a < b ? a : b;
}

class _TurnStatusStrip extends StatelessWidget {
  const _TurnStatusStrip({
    required this.localTurn,
    required this.sendingMove,
    required this.pulse,
    required this.pulseLocal,
    required this.compact,
  });

  final bool localTurn;
  final bool sendingMove;
  final bool pulse;
  final bool pulseLocal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final highlightedLocal = pulse ? pulseLocal : localTurn;
    final accent = highlightedLocal
        ? const Color(0xFF29D398)
        : const Color(0xFFFFC94D);
    final title = sendingMove
        ? 'SENDING MOVE…'
        : localTurn
        ? context.tr('your_turn').toUpperCase()
        : context.tr('opponents_turn').toUpperCase();
    final subtitle = sendingMove
        ? 'Syncing your move'
        : localTurn
        ? 'Make your move'
        : 'Waiting for opponent';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: compact ? 42 : 47,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xE60A1A24),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: accent.withValues(alpha: pulse ? .72 : .28),
        ),
        boxShadow: pulse
            ? [BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 16)]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            localTurn ? Icons.touch_app_rounded : Icons.hourglass_top_rounded,
            color: accent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: accent,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .55,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .60),
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArenaBottomControls extends StatelessWidget {
  const _ArenaBottomControls({
    required this.hub,
    required this.forfeiting,
    required this.onForfeit,
  });

  final OnlineDuelEmoteHub hub;
  final bool forfeiting;
  final VoidCallback onForfeit;

  Future<void> _showOptions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .46),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Material(
            color: const Color(0xFF101D27),
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'MATCH OPTIONS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: hub.muted ? 'Unmute' : 'Mute',
                        onPressed: hub.toggleMute,
                        icon: Icon(
                          hub.muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                        ),
                      ),
                    ],
                  ),
                  ListTile(
                    enabled: !forfeiting,
                    leading: const Icon(
                      Icons.flag_rounded,
                      color: Color(0xFFFF8C88),
                    ),
                    title: const Text(
                      'Forfeit match',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text('A second confirmation is required.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: forfeiting
                        ? null
                        : () => Navigator.of(sheetContext).pop('forfeit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (action == 'forfeit') onForfeit();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 45,
      child: Row(
        children: [
          _ArenaCircleButton(
            tooltip: 'Emotes',
            onPressed: hub.canSend
                ? () => showOnlineDuelEmotePicker(context, hub)
                : null,
            icon: Icons.add_reaction_outlined,
          ),
          const Spacer(),
          _ArenaCircleButton(
            tooltip: 'Match options',
            onPressed: () => _showOptions(context),
            icon: Icons.more_horiz_rounded,
          ),
        ],
      ),
    );
  }
}

class _ArenaCircleButton extends StatelessWidget {
  const _ArenaCircleButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xD8152532),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFC94D).withValues(alpha: .44),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: const Color(0xFFFFD66B), size: 23),
          ),
        ),
      ),
    );
  }
}

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.snapshot, required this.compact});

  final OnlineDuelSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 70.0 : 80.0;
    final timerSize = compact ? 55.0 : 64.0;
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            top: 8,
            bottom: 7,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xE8122235),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .09)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _HeaderPlayer(
                      snapshot: snapshot,
                      seat: OnlineDuelSeat.a,
                      compact: compact,
                    ),
                  ),
                  SizedBox(width: timerSize + 14),
                  Expanded(
                    child: _HeaderPlayer(
                      snapshot: snapshot,
                      seat: OnlineDuelSeat.b,
                      compact: compact,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _TimerPill(
            deadline: snapshot.turnDeadline,
            compact: compact,
            size: timerSize,
          ),
        ],
      ),
    );
  }
}

class _HeaderPlayer extends StatelessWidget {
  const _HeaderPlayer({
    required this.snapshot,
    required this.seat,
    required this.compact,
    this.alignEnd = false,
  });

  final OnlineDuelSnapshot snapshot;
  final OnlineDuelSeat seat;
  final bool compact;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final player = snapshot.players[seat]!;
    final local = snapshot.youSeat == seat;
    final active = snapshot.currentTurnSeat == seat;
    final accent = seat == OnlineDuelSeat.a
        ? const Color(0xFF29D398)
        : const Color(0xFFFFC94D);
    final name = local ? context.tr('you') : player.displayName;
    final score = snapshot.scores[seat] ?? 0;

    final avatar = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? accent : Colors.white.withValues(alpha: .34),
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: accent.withValues(alpha: .28), blurRadius: 12)]
            : null,
      ),
      child: PlayerAvatar(
        displayName: player.displayName,
        avatarKey: player.avatarKey,
        radius: compact ? 16 : 20,
        semanticLabel: name,
      ),
    );

    final info = Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Bronze III',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFC3A8FF),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${score > 0 ? '+' : ''}$score RP',
            style: TextStyle(
              color: score < 0
                  ? const Color(0xFFFF6B62)
                  : score > 0
                  ? const Color(0xFF29D398)
                  : Colors.white,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Row(
        textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
        children: [avatar, const SizedBox(width: 7), info],
      ),
    );
  }
}

class _TimerPill extends StatefulWidget {
  const _TimerPill({required this.deadline, required this.compact, this.size});

  final DateTime? deadline;
  final bool compact;
  final double? size;

  @override
  State<_TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends State<_TimerPill> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _secondsUntil(widget.deadline);
    final gameColors = Theme.of(context).extension<GameColors>()!;
    final color = seconds != null && seconds <= 5
        ? gameColors.timerCritical
        : seconds != null && seconds <= 10
        ? gameColors.warning
        : const Color(0xFF29D398);
    final size = widget.size ?? (widget.compact ? 54.0 : 64.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF3A4960), Color(0xFF202C40)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .28)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: .25), blurRadius: 12)],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(5),
            child: CircularProgressIndicator(
              value: seconds == null
                  ? null
                  : (seconds / 30).clamp(0.0, 1.0).toDouble(),
              strokeWidth: widget.compact ? 2.5 : 3,
              backgroundColor: Colors.white.withValues(alpha: .14),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seconds == null ? '--' : '$seconds',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.compact ? 21 : 25,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  's',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .52),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int? _secondsUntil(DateTime? deadline) {
    if (deadline == null) return null;
    final diff = deadline.difference(DateTime.now()).inMilliseconds;
    return diff <= 0 ? 0 : (diff / 1000).ceil();
  }
}
