import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/sudoku_board.dart';

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
  bool _loading = true;
  bool _screenLoadedSent = false;
  Timer? _ticker;
  Timer? _feedbackTimer;
  String? _shownResultFor;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_connect());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    unawaited(_controller?.dispose());
    _ticker?.cancel();
    _feedbackTimer?.cancel();
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
        setState(() {
          _snapshot = snapshot;
          _loading = false;
          _error = null;
        });
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

  Future<bool> _confirmLeave() async {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.isFinished) return true;
    final leave = await showDialog<bool>(
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
    if (leave == true) _controller?.forfeit();
    return leave == true;
  }

  void _selectCell(int index) {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.isFinished) return;
    if (!snapshot.isLocalTurn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sıra rakibinde'),
          duration: Duration(seconds: 1),
        ),
      );
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
    final index = _selectedIndex;
    if (index == null) return;
    _controller?.move(index, value);
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
    _shownResultFor = snapshot.matchId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_resultTitle(snapshot)),
          content: Text(_coinText(snapshot)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _snapshot?.isFinished ?? true,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 48,
          titleSpacing: 16,
          title: Text(context.tr('online_duel')),
        ),
        bottomNavigationBar: _snapshot == null
            ? null
            : NumberPadDock(
                child: NumberPad(
                  maxValue: 9,
                  completedValues: completedSudokuNumbers(
                    board: _snapshot!.board,
                    maxValue: 9,
                  ),
                  enabled:
                      _snapshot!.isLocalTurn &&
                      _controller?.pendingMove != true &&
                      !_snapshot!.isFinished,
                  onNumber: _enterNumber,
                  onErase: () => setState(() => _selectedIndex = null),
                ),
              ),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr('online_connection_failed', <Object>[_error!]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(child: Text(context.tr('online_waiting_snapshot')));
    }
    final puzzle = SudokuPuzzle(
      id: 'online-${snapshot.matchId}',
      title: 'Online Duel',
      difficulty: _difficulty(snapshot.difficulty),
      puzzle: snapshot.puzzle,
      solution: List<int>.filled(81, 1),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 520 || constraints.maxWidth < 380;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            compact ? 3 : 8,
            compact ? 8 : 12,
            compact ? 3 : 10,
          ),
          child: Column(
            children: [
              _ScoreHeader(snapshot: snapshot, compact: compact),
              SizedBox(height: compact ? 4 : 8),
              _TurnBanner(
                snapshot: snapshot,
                readySeconds: _secondsUntil(snapshot.readyDeadline),
                turnSeconds: _secondsUntil(snapshot.turnDeadline),
                compact: compact,
              ),
              if (snapshot.status == OnlineDuelStatus.readyWindow ||
                  snapshot.status == OnlineDuelStatus.waiting)
                Padding(
                  padding: EdgeInsets.only(top: compact ? 4 : 8),
                  child: _ReadyPanel(
                    snapshot: snapshot,
                    seconds: _secondsUntil(snapshot.readyDeadline),
                    onReady: _controller?.ready,
                    compact: compact,
                  ),
                ),
              SizedBox(height: compact ? 4 : 8),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SudokuBoard(
                      puzzle: puzzle,
                      board: snapshot.board,
                      selectedIndex: _selectedIndex,
                      errorIndex: _feedbackCell,
                      enabled: !snapshot.isFinished,
                      onCellTap: _selectCell,
                    ),
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 24,
                  child: Center(
                    child: Text(
                      _controller?.pendingMove == true
                          ? 'Hamle gönderiliyor'
                          : snapshot.isLocalTurn
                          ? 'Boş hücre seç ve rakam gir'
                          : 'Rakibin hamlesi bekleniyor',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  int? _secondsUntil(DateTime? deadline) {
    if (deadline == null) return null;
    final diff = deadline.difference(DateTime.now()).inMilliseconds;
    return diff <= 0 ? 0 : (diff / 1000).ceil();
  }

  String _resultTitle(OnlineDuelSnapshot snapshot) {
    if (snapshot.winnerSeat == null) return context.tr('draw');
    return snapshot.winnerSeat == snapshot.youSeat ? 'Kazandın!' : 'Kaybettin';
  }

  String _coinText(OnlineDuelSnapshot snapshot) {
    final delta = snapshot.coinSettlement?.deltas[snapshot.youSeat];
    if (delta == null || delta == 0) {
      return context.tr('online_final_score', <Object>[
        snapshot.scores[OnlineDuelSeat.a] ?? 0,
        snapshot.scores[OnlineDuelSeat.b] ?? 0,
      ]);
    }
    return 'Coin değişimi: ${delta > 0 ? '+' : ''}$delta Coin';
  }

  SudokuDifficulty _difficulty(String value) {
    return SudokuDifficulty.values.firstWhere(
      (difficulty) => difficulty.name == value,
      orElse: () => SudokuDifficulty.easy,
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.snapshot, required this.compact});

  final OnlineDuelSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlayerCard(
            snapshot: snapshot,
            seat: OnlineDuelSeat.a,
            compact: compact,
          ),
        ),
        SizedBox(width: compact ? 6 : 10),
        Expanded(
          child: _PlayerCard(
            snapshot: snapshot,
            seat: OnlineDuelSeat.b,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.snapshot,
    required this.seat,
    required this.compact,
  });

  final OnlineDuelSnapshot snapshot;
  final OnlineDuelSeat seat;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final player = snapshot.players[seat]!;
    final active = snapshot.currentTurnSeat == seat;
    final isLocalPlayer = snapshot.youSeat == seat;
    final scheme = Theme.of(context).colorScheme;
    final displayName = isLocalPlayer ? 'Sen' : player.displayName;

    if (compact) {
      return Card(
        margin: EdgeInsets.zero,
        color: active ? scheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (active) ...[
                Icon(Icons.circle, size: 8, color: scheme.primary),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${snapshot.scores[seat] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              if (!player.connected) ...[
                const SizedBox(width: 4),
                const Icon(Icons.wifi_off_rounded, size: 15),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      color: active ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${snapshot.scores[seat] ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              player.connected
                  ? context.tr('connected')
                  : context.tr('reconnecting'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.snapshot,
    required this.readySeconds,
    required this.turnSeconds,
    required this.compact,
  });

  final OnlineDuelSnapshot snapshot;
  final int? readySeconds;
  final int? turnSeconds;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = snapshot.isLocalTurn
        ? context.tr('your_turn')
        : context.tr('opponents_turn');
    final subtitle = snapshot.status == OnlineDuelStatus.active
        ? compact
              ? '${turnSeconds ?? 0} sn'
              : 'Hamle süresi: ${turnSeconds ?? 0}'
        : snapshot.status == OnlineDuelStatus.readyWindow
        ? compact
              ? '${readySeconds ?? 0} sn'
              : 'Otomatik başlangıç: ${readySeconds ?? 0}'
        : context.tr('online_turn_number', <Object>[snapshot.turnNumber]);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: snapshot.isLocalTurn
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: compact ? 18 : 24),
            SizedBox(width: compact ? 5 : 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w900),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyPanel extends StatelessWidget {
  const _ReadyPanel({
    required this.snapshot,
    required this.seconds,
    required this.onReady,
    required this.compact,
  });

  final OnlineDuelSnapshot snapshot;
  final int? seconds;
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
        ? 'Rakip bağlanıyor'
        : !opponent.screenLoaded
        ? 'Rakip oyunu açıyor'
        : 'Rakip hazır';
    final countdownText = seconds == null ? '' : ' • $seconds sn';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$opponentStatus$countdownText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: compact
                  ? Theme.of(context).textTheme.bodySmall
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          FilledButton.icon(
            onPressed: you.ready ? null : onReady,
            style: compact
                ? FilledButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                : null,
            icon: Icon(
              you.ready ? Icons.check_circle : Icons.check_circle_outline,
              size: compact ? 17 : 24,
            ),
            label: Text(you.ready ? 'Hazırsın' : 'Ben hazırım'),
          ),
        ],
      ),
    );
  }
}
