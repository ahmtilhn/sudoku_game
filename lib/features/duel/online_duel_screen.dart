import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
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
  String? _shownResultFor;
  int _resultSettlementAttempts = 0;
  bool _forfeiting = false;
  bool _localConnectionInterrupted = false;

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
        _markProgress(previous, snapshot);
        setState(() {
          _snapshot = snapshot;
          _loading = false;
          _error = null;
          if (!snapshot.isLocalTurn) _selectedIndex = null;
          if (snapshot.isFinished) _forfeiting = false;
        });
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
    await _returnToMainMenu(sendForfeit: true);
  }

  Future<void> _returnToMainMenu({required bool sendForfeit}) async {
    if (sendForfeit) {
      setState(() => _forfeiting = true);
      _controller?.forfeit();
      _controller?.requestSnapshot();
      final settled = await waitForAuthoritativeResult();
      if (!mounted) return;
      if (!settled) {
        setState(() => _forfeiting = false);
        _controller?.requestSnapshot();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('connection_interrupted_retrying')),
          ),
        );
        return;
      }
    }
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
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
    if (snapshot == null || snapshot.isFinished) {
      return;
    }
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
    setState(() {
      if (!localChanged) {
        _opponentMoveIndexes
          ..clear()
          ..addAll(changed);
      }
    });
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
      await EconomyService.instance.refresh(showLoading: false);
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .46),
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (sheetContext) => _OnlineResultSheet(snapshot: snapshot),
      );
      if (!mounted || action == null) return;
      if (action.startsWith('rematch:')) {
        final roomId = action.substring('rematch:'.length);
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(
            builder: (_) => PreMatchReadyScreen(roomId: roomId),
          ),
        );
      } else if (action == 'new_match') {
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
        );
      } else if (action == 'menu') {
        Navigator.of(context).pop(action);
      }
    });
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
        backgroundColor: activeArena ? const Color(0xFF0B1215) : null,
        bottomNavigationBar: snapshot == null
            ? null
            : Theme(
                data: activeArena ? _arenaTheme(context) : Theme.of(context),
                child: IgnorePointer(
                  ignoring: inputLocked,
                  child: NumberPadDock(
                    compact: activeArena,
                    child: NumberPad(
                      maxValue: snapshot.boardSize,
                      completedValues: completedSudokuNumbers(
                        board: snapshot.board,
                        maxValue: snapshot.boardSize,
                      ),
                      enabled: !inputLocked,
                      onNumber: _enterNumber,
                      onErase: () => setState(() => _selectedIndex = null),
                    ),
                  ),
                ),
              ),
        body: Theme(
          data: activeArena ? _arenaTheme(context) : Theme.of(context),
          child: activeArena
              ? AppBackdrop(
                  dim: .44,
                  child: SafeArea(child: _buildBody(context)),
                )
              : SafeArea(child: _buildBody(context)),
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
      scaffoldBackgroundColor: const Color(0xFF0B1215),
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
                      context.tr('online_connection_failed', <Object>[_error!]),
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
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: InPageHeader(title: context.tr('online_duel')),
          ),
          Expanded(
            child: Center(child: Text(context.tr('online_waiting_snapshot'))),
          ),
        ],
      );
    }
    final puzzle = SudokuPuzzle(
      id: 'online-${snapshot.matchId}',
      title: 'Online Duel',
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
            statusText: _forfeiting
                ? context.tr('connection_interrupted_retrying')
                : _controller?.pendingMove == true
                ? context.tr('sending_move')
                : snapshot.isLocalTurn
                ? context.tr('select_empty_cell_enter_number')
                : context.tr('waiting_opponent_move'),
            onForfeit: _requestForfeit,
            forfeiting: _forfeiting,
          );
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            compact ? 3 : 8,
            compact ? 8 : 12,
            compact ? 3 : 10,
          ),
          child: Column(
            children: [
              InPageHeader(
                title: context.strings.difficultyLabel(
                  _difficulty(snapshot.difficulty),
                ),
                padding: EdgeInsets.only(bottom: compact ? 4 : 8),
              ),
              if (snapshot.status == OnlineDuelStatus.readyWindow ||
                  snapshot.status == OnlineDuelStatus.waiting)
                Padding(
                  padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                  child: _ReadyPanel(
                    snapshot: snapshot,
                    onReady: _controller?.ready,
                    compact: compact,
                  ),
                ),
              if (snapshot.status == OnlineDuelStatus.paused)
                Padding(
                  padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                  child: Text(
                    context.tr('opponent_connecting'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: _localConnectionInterrupted
                          ? Theme.of(context).colorScheme.tertiary
                          : null,
                    ),
                  ),
                ),
              Expanded(
                child: Center(child: AspectRatio(aspectRatio: 1, child: board)),
              ),
            ],
          ),
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
  bool _busy = false;
  String? _statusMessage;

  OnlineDuelSnapshot get snapshot => widget.snapshot;

  OnlineDuelSeat get opponentSeat => snapshot.youSeat == OnlineDuelSeat.a
      ? OnlineDuelSeat.b
      : OnlineDuelSeat.a;

  OnlineDuelPlayer get opponent => snapshot.players[opponentSeat]!;

  OnlineDuelPlayer get winnerPlayer {
    final winnerSeat = snapshot.winnerSeat;
    if (winnerSeat == null) return snapshot.players[snapshot.youSeat]!;
    return snapshot.players[winnerSeat]!;
  }

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

  @override
  Widget build(BuildContext context) {
    final localScore = snapshot.scores[snapshot.youSeat] ?? 0;
    final opponentScore = snapshot.scores[opponentSeat] ?? 0;
    final rating = snapshot.rating?[snapshot.youSeat];
    final won = snapshot.winnerSeat == snapshot.youSeat;
    final entryFee = _economy.entryFeeForDifficulty(snapshot.difficulty);
    final resultTitle = snapshot.winnerSeat == null
        ? context.tr('draw')
        : won
        ? context.tr('you_won')
        : context.tr('you_lost');
    final resultSubtitle = snapshot.winnerSeat == null
        ? context.tr('result_draw_subtitle')
        : won
        ? context.tr('result_win_subtitle')
        : context.tr('result_loss_subtitle');
    final you = snapshot.players[snapshot.youSeat]!;
    final localRating = rating?.afterGlobal ?? 1000;
    final opponentRating =
        snapshot.rating?[opponentSeat]?.afterGlobal ?? (localRating + 0);
    final canPlay = _economy.balance >= entryFee;
    final invite = _invitation;
    final seconds = invite == null
        ? 0
        : invite.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 10);
    final draw = snapshot.winnerSeat == null;
    final localNetCoin = draw
        ? 0
        : won
        ? entryFee
        : -entryFee;
    final opponentNetCoin = -localNetCoin;
    String coinLabel(int value) =>
        '${value > 0 ? '+' : ''}${context.tr('coin_amount', <Object>[value])}';
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (snapshot.mode == 'friendly') ...[
          Text(
            '${context.tr('challenge')} · ${context.tr('result_elo_change')}: 0',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .68),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        if (_statusMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _statusMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF29D398),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        if (invite != null && invite.status == 'pending') ...[
          const SizedBox(height: 12),
          _ResultInvitationPanel(
            invite: invite,
            opponentName: opponent.displayName,
            seconds: seconds,
            busy: _busy,
            canPlay: canPlay,
            onDecline: () => _respond(invite, false),
            onAccept: () => _respond(invite, true),
          ),
        ],
        const SizedBox(height: 14),
        _ResultActionGrid(
          busy: _busy,
          canPlay: canPlay,
          invitePending: invite?.status == 'pending',
          onRematch: _createRematch,
          onNewMatch: () => Navigator.of(context).pop('new_match'),
          onAddFriend: _addFriend,
          onMenu: () => Navigator.of(context).pop('menu'),
        ),
        if (!canPlay) ...[
          const SizedBox(height: 10),
          Text(
            context.tr('not_enough_coins_online', <Object>[entryFee]),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFFB4AB),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CoinStoreScreen())),
            icon: const DuelAssetIcon(DuelAsset.store, size: 22),
            label: Text(context.tr('open_coin_store')),
          ),
        ],
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        14,
        6,
        14,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ResultShowcaseCard(
            title: resultTitle,
            subtitle: resultSubtitle,
            won: won,
            draw: snapshot.winnerSeat == null,
            localPlayer: you,
            opponent: opponent,
            localScore: localScore,
            opponentScore: opponentScore,
            localRating: localRating,
            opponentRating: opponentRating,
            rating: rating,
            footer: footer,
            rows: [
              _ResultMetric(
                label: context.tr('correct_moves'),
                localValue: '${snapshot.correctMoves[snapshot.youSeat] ?? 0}',
                opponentValue: '${snapshot.correctMoves[opponentSeat] ?? 0}',
                asset: DuelAsset.check,
              ),
              _ResultMetric(
                label: context.tr('mistakes'),
                localValue: '${snapshot.mistakes[snapshot.youSeat] ?? 0}',
                opponentValue: '${snapshot.mistakes[opponentSeat] ?? 0}',
                asset: DuelAsset.close,
              ),
              _ResultMetric(
                label: context.tr('timeouts'),
                localValue: '${snapshot.timeouts[snapshot.youSeat] ?? 0}',
                opponentValue: '${snapshot.timeouts[opponentSeat] ?? 0}',
                asset: DuelAsset.timer,
              ),
              _ResultMetric(
                label: context.tr('hints'),
                localValue: context.tr('not_available_short'),
                opponentValue: context.tr('not_available_short'),
                asset: DuelAsset.lightbulb,
              ),
              _ResultMetric(
                label: context.tr('coin_result'),
                localValue: coinLabel(localNetCoin),
                opponentValue: coinLabel(opponentNetCoin),
                asset: DuelAsset.coin,
              ),
            ],
          ),
        ],
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
      if (relevant.status == 'accepted' &&
          relevant.roomId?.isNotEmpty == true) {
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
    _pollTimer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop('rematch:$roomId');
  }

  Future<void> _addFriend() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await SocialApiClient.instance.sendFriendRequest(opponent.publicId);
      if (!mounted) return;
      setState(() => _statusMessage = context.tr('friend_request_sent'));
    } on SocialApiException catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ResultMetric {
  const _ResultMetric({
    required this.label,
    required this.localValue,
    required this.opponentValue,
    required this.asset,
  });

  final String label;
  final String localValue;
  final String opponentValue;
  final String asset;
}

class _ResultShowcaseCard extends StatelessWidget {
  const _ResultShowcaseCard({
    required this.title,
    required this.subtitle,
    required this.won,
    required this.draw,
    required this.localPlayer,
    required this.opponent,
    required this.localScore,
    required this.opponentScore,
    required this.localRating,
    required this.opponentRating,
    required this.rating,
    required this.rows,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final bool won;
  final bool draw;
  final OnlineDuelPlayer localPlayer;
  final OnlineDuelPlayer opponent;
  final int localScore;
  final int opponentScore;
  final int localRating;
  final int opponentRating;
  final OnlineDuelRatingChange? rating;
  final List<_ResultMetric> rows;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final accent = draw
        ? const Color(0xFF8DA2BE)
        : won
        ? const Color(0xFF1E9B63)
        : const Color(0xFFC15B55);
    final banner = draw
        ? const Color(0xFF4D627E)
        : won
        ? const Color(0xFF128151)
        : const Color(0xFF9E403B);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF172235),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .24),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _ResultSurfacePainter(accent)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ResultCrown(accent: accent),
                  const SizedBox(height: 4),
                  _ResultBanner(title: title, color: banner),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .86),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ResultPlayersRow(
                    localPlayer: localPlayer,
                    opponent: opponent,
                    localScore: localScore,
                    opponentScore: opponentScore,
                    localRating: localRating,
                    opponentRating: opponentRating,
                    accent: accent,
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          for (final row in rows) _ResultCompareRow(row: row),
                        ],
                      ),
                    ),
                  ),
                  if (rating != null) ...[
                    const SizedBox(height: 12),
                    _ResultEloBar(rating: rating!, color: accent),
                  ],
                  footer,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultSurfacePainter extends CustomPainter {
  const _ResultSurfacePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -1),
        radius: .9,
        colors: [color.withValues(alpha: .08), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);

    final line = Paint()
      ..color = Colors.white.withValues(alpha: .05)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (.18 + i * .16);
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _ResultSurfacePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ResultCrown extends StatelessWidget {
  const _ResultCrown({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DuelAssetIcon(
      DuelAsset.shield,
      color: const Color(0xFFFFC94D),
      size: 52,
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
        child: Text(
          title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFFFEAA6),
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ResultPlayersRow extends StatelessWidget {
  const _ResultPlayersRow({
    required this.localPlayer,
    required this.opponent,
    required this.localScore,
    required this.opponentScore,
    required this.localRating,
    required this.opponentRating,
    required this.accent,
  });

  final OnlineDuelPlayer localPlayer;
  final OnlineDuelPlayer opponent;
  final int localScore;
  final int opponentScore;
  final int localRating;
  final int opponentRating;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF243149),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: _ResultPlayerSummary(
                player: localPlayer,
                score: localScore,
                rating: localRating,
                color: const Color(0xFF1E9B63),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                context.tr('versus_short'),
                style: TextStyle(
                  color: const Color(0xFFFFC94D).withValues(alpha: .95),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: _ResultPlayerSummary(
                player: opponent,
                score: opponentScore,
                rating: opponentRating,
                color: accent,
                alignEnd: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPlayerSummary extends StatelessWidget {
  const _ResultPlayerSummary({
    required this.player,
    required this.score,
    required this.rating,
    required this.color,
    this.alignEnd = false,
  });

  final OnlineDuelPlayer player;
  final int score;
  final int rating;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      _AvatarRing(
        color: color,
        active: true,
        child: PlayerAvatar(
          displayName: player.displayName,
          avatarKey: player.avatarKey,
          radius: 19,
          semanticLabel: context.tr('player_avatar_semantics', <Object>[
            player.displayName,
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              player.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$score',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            Text(
              context.tr('rating_value', <Object>[rating]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .72),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ];
    return Row(
      textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
      children: content,
    );
  }
}

class _ResultCompareRow extends StatelessWidget {
  const _ResultCompareRow({required this.row});

  final _ResultMetric row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              row.localValue,
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: Color(0xFF41C182),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DuelAssetIcon(
                  row.asset,
                  size: 15,
                  color: const Color(0xFFFFC94D),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              row.opponentValue,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xFF6EA0D8),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultEloBar extends StatelessWidget {
  const _ResultEloBar({required this.rating, required this.color});

  final OnlineDuelRatingChange rating;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final before = rating.beforeGlobal;
    final after = rating.afterGlobal;
    final delta = rating.deltaGlobal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('result_elo_change'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .72),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Text(
              '$before',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 9,
                  child: LinearProgressIndicator(
                    value: (after / 2500).clamp(.05, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: .12),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$after (${delta >= 0 ? '+' : ''}$delta)',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultInvitationPanel extends StatelessWidget {
  const _ResultInvitationPanel({
    required this.invite,
    required this.opponentName,
    required this.seconds,
    required this.busy,
    required this.canPlay,
    required this.onDecline,
    required this.onAccept,
  });

  final RematchInvitation invite;
  final String opponentName;
  final int seconds;
  final bool busy;
  final bool canPlay;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: invite.isSender
            ? Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('waiting_for_player_seconds', <Object>[
                        opponentName,
                        seconds,
                      ]),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('wants_rematch_seconds', <Object>[
                      invite.sender.displayName,
                      seconds,
                    ]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                          child: Text(context.tr('accept')),
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

class _ResultActionGrid extends StatelessWidget {
  const _ResultActionGrid({
    required this.busy,
    required this.canPlay,
    required this.invitePending,
    required this.onRematch,
    required this.onNewMatch,
    required this.onAddFriend,
    required this.onMenu,
  });

  final bool busy;
  final bool canPlay;
  final bool invitePending;
  final VoidCallback onRematch;
  final VoidCallback onNewMatch;
  final VoidCallback onAddFriend;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final primary = _ResultActionButton(
      asset: DuelAsset.refresh,
      label: context.tr('challenge_again'),
      onPressed: busy || !canPlay || invitePending ? null : onRematch,
      filled: false,
    );
    final next = _ResultActionButton(
      asset: DuelAsset.arrowForward,
      label: context.tr('find_new_match'),
      onPressed: busy || !canPlay ? null : onNewMatch,
      filled: true,
    );
    final friend = _ResultActionButton(
      asset: DuelAsset.people,
      label: context.tr('add_friend'),
      onPressed: busy ? null : onAddFriend,
      filled: false,
    );
    final menu = _ResultActionButton(
      asset: DuelAsset.home,
      label: context.tr('main_menu'),
      onPressed: busy ? null : onMenu,
      filled: false,
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: primary),
            const SizedBox(width: 8),
            Expanded(child: next),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: friend),
            const SizedBox(width: 8),
            Expanded(child: menu),
          ],
        ),
      ],
    );
  }
}

class _ResultActionButton extends StatelessWidget {
  const _ResultActionButton({
    required this.asset,
    required this.label,
    required this.onPressed,
    required this.filled,
  });

  final String asset;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = filled
        ? FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: const Color(0xFF1E9B63),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          )
        : OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: .18)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          );
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuelAssetIcon(asset, size: 18),
          const SizedBox(width: 6),
          Text(label, maxLines: 1),
        ],
      ),
    );
    return filled
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _ArenaMatchLayout extends StatelessWidget {
  const _ArenaMatchLayout({
    required this.snapshot,
    required this.compact,
    required this.board,
    required this.statusText,
    required this.onForfeit,
    required this.forfeiting,
  });

  final OnlineDuelSnapshot snapshot;
  final bool compact;
  final Widget board;
  final String statusText;
  final VoidCallback onForfeit;
  final bool forfeiting;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C2638), Color(0xFF273347), Color(0xFF182132)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 5 : 8,
          compact ? 4 : 7,
          compact ? 5 : 8,
          compact ? 4 : 7,
        ),
        child: Column(
          children: [
            _MatchHeader(snapshot: snapshot, compact: compact),
            SizedBox(height: compact ? 3 : 5),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final railWidth = wide ? 54.0 : 0.0;
                  final historyWidth = wide ? 82.0 : 0.0;
                  final horizontalChrome =
                      railWidth + historyWidth + (wide ? 10.0 : 0.0);
                  final boardMax =
                      constraints.maxHeight <
                          constraints.maxWidth - horizontalChrome
                      ? constraints.maxHeight
                      : constraints.maxWidth - horizontalChrome;
                  final boardSize = wide
                      ? boardMax.clamp(300.0, 680.0)
                      : boardMax.clamp(280.0, 640.0);
                  final boardWidget = Center(
                    child: SizedBox.square(
                      dimension: boardSize,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF3D74B6,
                              ).withValues(alpha: .14),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: board,
                      ),
                    ),
                  );
                  if (!wide) return boardWidget;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(width: 54, child: _ArenaToolRail()),
                      Expanded(child: boardWidget),
                      SizedBox(
                        width: 82,
                        child: _MoveHistoryPanel(snapshot: snapshot),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: compact ? 3 : 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: .58),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: forfeiting ? null : onForfeit,
                  icon: forfeiting
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.flag_rounded, size: 16),
                  label: Text(context.tr('forfeit_and_leave')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB4AB),
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(44, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

class _ArenaToolRail extends StatelessWidget {
  const _ArenaToolRail();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArenaToolButton(asset: DuelAsset.lightbulb, label: context.tr('hint')),
        const SizedBox(height: 8),
        _ArenaToolButton(asset: DuelAsset.notes, label: context.tr('notes')),
        const SizedBox(height: 8),
        _ArenaToolButton(asset: DuelAsset.undo, label: context.tr('undo')),
      ],
    );
  }
}

class _ArenaToolButton extends StatelessWidget {
  const _ArenaToolButton({required this.asset, required this.label});

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2E3A50).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF5A6A82)),
      ),
      child: Column(
        children: [
          DuelAssetIcon(asset, color: const Color(0xFFFFC94D), size: 17),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .88),
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveHistoryPanel extends StatelessWidget {
  const _MoveHistoryPanel({required this.snapshot});

  final OnlineDuelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
        ? OnlineDuelSeat.b
        : OnlineDuelSeat.a;
    final opponent = snapshot.players[opponentSeat]!;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF2B374D).withValues(alpha: .96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5A6A82)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('last_move'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: .86),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _HistoryDot(
            color: const Color(0xFFE0B64B),
            label: opponent.displayName,
            value: '${snapshot.scores[opponentSeat] ?? 0}',
          ),
          const SizedBox(height: 8),
          _HistoryDot(
            color: const Color(0xFF3D74B6),
            label: context.tr('you'),
            value: '${snapshot.scores[snapshot.youSeat] ?? 0}',
          ),
        ],
      ),
    );
  }
}

class _HistoryDot extends StatelessWidget {
  const _HistoryDot({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.snapshot, required this.compact});

  final OnlineDuelSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scoreA = snapshot.scores[OnlineDuelSeat.a] ?? 0;
    final scoreB = snapshot.scores[OnlineDuelSeat.b] ?? 0;
    final total = (scoreA.abs() + scoreB.abs()).clamp(1, 999999);
    final scheme = Theme.of(context).colorScheme;
    final height = compact ? 70.0 : 82.0;
    final timerSize = compact ? 54.0 : 64.0;

    return Semantics(
      label: context.tr('match_header_semantics'),
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(
              top: compact ? 9 : 11,
              bottom: compact ? 8 : 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF172435).withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .28),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: scheme.tertiary.withValues(alpha: .10),
                      blurRadius: 16,
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              top: compact ? 9 : 11,
              bottom: compact ? 8 : 10,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HeaderCircuitPainter(
                    primary: scheme.primary,
                    tertiary: scheme.tertiary,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              top: compact ? 12 : 14,
              bottom: compact ? 13 : 15,
              child: Row(
                children: [
                  Expanded(
                    child: _DuelPlayerPlate(
                      snapshot: snapshot,
                      seat: OnlineDuelSeat.a,
                      compact: compact,
                    ),
                  ),
                  SizedBox(width: timerSize + (compact ? 12 : 18)),
                  Expanded(
                    child: _DuelPlayerPlate(
                      snapshot: snapshot,
                      seat: OnlineDuelSeat.b,
                      compact: compact,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: _TimerPill(
                deadline: snapshot.turnDeadline,
                compact: compact,
                size: timerSize,
              ),
            ),
            Positioned(
              left: compact ? 14 : 24,
              right: compact ? 14 : 24,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .24),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: compact ? 3 : 4,
                    child: Row(
                      children: [
                        Expanded(
                          flex: ((scoreA.abs() / total) * 1000)
                              .round()
                              .clamp(1, 999)
                              .toInt(),
                          child: ColoredBox(color: scheme.primary),
                        ),
                        Expanded(
                          flex: ((scoreB.abs() / total) * 1000)
                              .round()
                              .clamp(1, 999)
                              .toInt(),
                          child: ColoredBox(color: scheme.tertiary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCircuitPainter extends CustomPainter {
  const _HeaderCircuitPainter({required this.primary, required this.tertiary});

  final Color primary;
  final Color tertiary;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * .5;
    final center = size.width * .5;
    final gap = size.height * .62;
    final linePaint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        colors: [
          primary.withValues(alpha: .42),
          Colors.white.withValues(alpha: .08),
          tertiary.withValues(alpha: .42),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawLine(Offset(0, midY), Offset(center - gap, midY), linePaint);
    canvas.drawLine(
      Offset(center + gap, midY),
      Offset(size.width, midY),
      linePaint,
    );

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: .12);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center, midY),
        width: size.height * .98,
        height: size.height * .98,
      ),
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant _HeaderCircuitPainter oldDelegate) {
    return oldDelegate.primary != primary || oldDelegate.tertiary != tertiary;
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
    final scheme = Theme.of(context).colorScheme;
    final gameColors = Theme.of(context).extension<GameColors>()!;
    final seconds = _secondsUntil(widget.deadline);
    final color = seconds != null && seconds <= 5
        ? gameColors.timerCritical
        : seconds != null && seconds <= 10
        ? gameColors.warning
        : scheme.primary;
    final size = widget.size ?? (widget.compact ? 52.0 : 70.0);
    return Container(
      key: const ValueKey<String>('online-turn-timer'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF3A4960), Color(0xFF222D40)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .30)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .28), blurRadius: 12),
          BoxShadow(
            color: Colors.black.withValues(alpha: .36),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(5),
            child: CircularProgressIndicator(
              value: seconds == null ? null : (seconds / 30).clamp(0.0, 1.0),
              strokeWidth: widget.compact ? 2.4 : 3,
              backgroundColor: Colors.white.withValues(alpha: .18),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${seconds ?? 0}',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.compact ? 22 : 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    context.tr('seconds_short'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .64),
                      fontSize: widget.compact ? 8 : 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
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

class _DuelPlayerPlate extends StatelessWidget {
  const _DuelPlayerPlate({
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
    final active = snapshot.currentTurnSeat == seat;
    final isLocalPlayer = snapshot.youSeat == seat;
    final scheme = Theme.of(context).colorScheme;
    final accent = seat == OnlineDuelSeat.a ? scheme.primary : scheme.tertiary;
    final displayName = isLocalPlayer ? context.tr('you') : player.displayName;
    final score = snapshot.scores[seat] ?? 0;
    final avatarRadius = compact ? 16.0 : 21.0;
    final seatKey = seat == OnlineDuelSeat.a ? 'A' : 'B';
    final avatar = KeyedSubtree(
      key: ValueKey<String>('duel-avatar-$seatKey'),
      child: _AvatarRing(
        color: accent,
        active: active,
        child: PlayerAvatar(
          displayName: player.displayName,
          avatarKey: player.avatarKey,
          radius: avatarRadius,
          semanticLabel: context.tr('player_avatar_semantics', <Object>[
            displayName,
          ]),
        ),
      ),
    );
    final children = <Widget>[
      avatar,
      SizedBox(width: compact ? 5 : 8),
      Expanded(
        child: Column(
          crossAxisAlignment: alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact)
              Align(
                alignment: alignEnd
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: alignEnd
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: Column(
                    crossAxisAlignment: alignEnd
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        key: ValueKey<String>('duel-name-$seatKey'),
                        displayName,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _ScoreLine(
                        key: ValueKey<String>('duel-score-$seatKey'),
                        score: score,
                        connected: player.connected,
                        color: accent,
                      ),
                    ],
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: alignEnd
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      key: ValueKey<String>('duel-name-$seatKey'),
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            if (!compact) ...[
              const SizedBox(height: 3),
              Align(
                alignment: alignEnd
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: _ScoreLine(
                  key: ValueKey<String>('duel-score-$seatKey'),
                  score: score,
                  connected: player.connected,
                  color: accent,
                ),
              ),
            ],
          ],
        ),
      ),
    ];
    final compactChildren = <Widget>[
      children[0],
      children[1],
      if (children[2] case final Expanded info) info.child else children[2],
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: active
            ? [BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 14)]
            : null,
      ),
      child: compact
          ? Align(
              alignment: alignEnd
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: alignEnd
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: compactChildren,
                ),
              ),
            )
          : Row(
              textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
              children: children,
            ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({
    required this.child,
    required this.color,
    required this.active,
  });

  final Widget child;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? color : Colors.white.withValues(alpha: .38),
          width: active ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: active ? .30 : .12),
            blurRadius: active ? 12 : 6,
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: child),
    );
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    super.key,
    required this.score,
    required this.connected,
    required this.color,
  });

  final int score;
  final bool connected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final negative = score < 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuelAssetIcon(DuelAsset.trophy, size: 13, color: scheme.tertiary),
        const SizedBox(width: 3),
        Text(
          '$score',
          style: TextStyle(
            color: negative
                ? const Color(0xFFFF5B6B)
                : Colors.white.withValues(alpha: .96),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        DuelAssetIcon(
          connected ? DuelAsset.wifi : DuelAsset.cloud,
          size: 12,
          color: connected ? color : scheme.error,
        ),
      ],
    );
  }
}

class _ReadyPanel extends StatelessWidget {
  const _ReadyPanel({
    required this.snapshot,
    required this.onReady,
    required this.compact,
  });

  final OnlineDuelSnapshot snapshot;
  final VoidCallback? onReady;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final you = snapshot.players[snapshot.youSeat]!;
    final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
        ? OnlineDuelSeat.b
        : OnlineDuelSeat.a;
    final opponent = snapshot.players[opponentSeat]!;
    final opponentStatus = !opponent.connected
        ? context.tr('opponent_connecting')
        : !opponent.screenLoaded
        ? context.tr('opponent_opening_game')
        : context.tr('opponent_ready');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final readyButton = FilledButton.icon(
            onPressed: you.ready ? null : onReady,
            icon: DuelAssetIcon(
              you.ready ? DuelAsset.check : DuelAsset.shield,
              size: compact ? 17 : 24,
            ),
            label: Text(
              you.ready ? context.tr('ready') : context.tr('i_am_ready'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
          final status = Row(
            children: [
              Expanded(
                child: Text(
                  opponentStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: compact
                      ? Theme.of(context).textTheme.bodySmall
                      : Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 6),
              _CountdownText(deadline: snapshot.readyDeadline),
            ],
          );
          if (compact || constraints.maxWidth < 360) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [status, const SizedBox(height: 6), readyButton],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 8),
              readyButton,
            ],
          );
        },
      ),
    );
  }
}

class _CountdownText extends StatefulWidget {
  const _CountdownText({required this.deadline});

  final DateTime? deadline;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
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
    if (seconds == null) return const SizedBox.shrink();
    return Text(
      context.tr('turn_timer_seconds', <Object>[seconds]),
      style: const TextStyle(fontWeight: FontWeight.w800),
    );
  }

  int? _secondsUntil(DateTime? deadline) {
    if (deadline == null) return null;
    final diff = deadline.difference(DateTime.now()).inMilliseconds;
    return diff <= 0 ? 0 : (diff / 1000).ceil();
  }
}
