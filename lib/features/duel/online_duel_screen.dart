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
        setState(() {
          _feedbackCell = feedback.cellIndex;
          if (feedback.accepted) _selectedIndex = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(feedback.message),
            duration: const Duration(seconds: 1),
          ),
        );
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
        appBar: AppBar(title: Text(context.tr('online_duel'))),
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
        final compact = constraints.maxHeight < 560;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            compact ? 4 : 8,
            12,
            compact ? 6 : 10,
          ),
          child: Column(
            children: [
              _ScoreHeader(snapshot: snapshot, compact: compact),
              SizedBox(height: compact ? 4 : 8),
              _TurnBanner(
                snapshot: snapshot,
                readySeconds: _secondsUntil(snapshot.readyDeadline),
                turnSeconds: _secondsUntil(snapshot.turnDeadline),
              ),
              if (snapshot.status == OnlineDuelStatus.readyWindow ||
                  snapshot.status == OnlineDuelStatus.waiting)
                Padding(
                  padding: EdgeInsets.only(top: compact ? 4 : 8),
                  child: _ReadyPanel(
                    snapshot: snapshot,
                    seconds: _secondsUntil(snapshot.readyDeadline),
                    onReady: _controller?.ready,
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
              SizedBox(height: compact ? 4 : 8),
              SizedBox(
                height: compact ? 20 : 24,
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
        const SizedBox(width: 10),
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: active ? scheme.primaryContainer : null,
      child: Padding(
        padding: EdgeInsets.all(compact ? 6 : 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              player.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: compact ? 2 : 4),
            Text('${snapshot.scores[seat] ?? 0}'),
            Text(
              player.connected
                  ? context.tr('connected')
                  : context.tr('reconnecting'),
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
  });

  final OnlineDuelSnapshot snapshot;
  final int? readySeconds;
  final int? turnSeconds;

  @override
  Widget build(BuildContext context) {
    final text = snapshot.isLocalTurn
        ? context.tr('your_turn')
        : context.tr('opponents_turn');
    final subtitle = snapshot.status == OnlineDuelStatus.active
        ? 'Hamle süresi: ${turnSeconds ?? 0}'
        : snapshot.status == OnlineDuelStatus.readyWindow
        ? 'Otomatik başlangıç: ${readySeconds ?? 0}'
        : context.tr('online_turn_number', <Object>[snapshot.turnNumber]);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: snapshot.isLocalTurn
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined),
            const SizedBox(width: 8),
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
  });

  final OnlineDuelSnapshot snapshot;
  final int? seconds;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    final you = snapshot.players[snapshot.youSeat]!;
    final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
        ? OnlineDuelSeat.b
        : OnlineDuelSeat.a;
    final opponent = snapshot.players[opponentSeat]!;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Rakip: ${opponent.connected ? 'bağlandı' : 'bekleniyor'} | ekran: ${opponent.screenLoaded ? 'hazır' : 'bekleniyor'} | başlangıç: ${seconds ?? '-'}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: you.ready ? null : onReady,
          icon: Icon(
            you.ready ? Icons.check_circle : Icons.check_circle_outline,
          ),
          label: Text(you.ready ? 'Hazırsın' : 'Ben hazırım'),
        ),
      ],
    );
  }
}
