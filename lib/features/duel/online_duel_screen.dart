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
  OnlineDuelSnapshot? _snapshot;
  Object? _error;
  int? _selectedIndex;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_controller?.dispose());
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
      });
      setState(() {
        _controller = controller;
        _subscription = subscription;
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
    if (snapshot == null ||
        !snapshot.isLocalTurn ||
        snapshot.puzzle[index] != 0 ||
        snapshot.board[index] != 0 ||
        _controller?.pendingMove == true) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _enterNumber(int value) {
    final index = _selectedIndex;
    if (index == null) return;
    final sent = _controller?.move(index, value) ?? false;
    if (sent) setState(() => _selectedIndex = null);
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
          title: Text(context.tr('online_duel')),
          actions: [
            IconButton(
              tooltip: context.tr('refresh'),
              onPressed: _controller?.requestSnapshot,
              icon: const Icon(Icons.sync),
            ),
          ],
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _ScoreHeader(snapshot: snapshot),
        const SizedBox(height: 12),
        _TurnBanner(snapshot: snapshot),
        const SizedBox(height: 12),
        SudokuBoard(
          puzzle: puzzle,
          board: snapshot.board,
          selectedIndex: _selectedIndex,
          enabled: snapshot.isLocalTurn && !snapshot.isFinished,
          onCellTap: _selectCell,
        ),
        const SizedBox(height: 16),
        if (snapshot.status == OnlineDuelStatus.waiting)
          FilledButton.icon(
            onPressed: _controller?.ready,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(context.tr('ready')),
          ),
        if (snapshot.isFinished) _ResultPanel(snapshot: snapshot),
      ],
    );
  }

  SudokuDifficulty _difficulty(String value) {
    return SudokuDifficulty.values.firstWhere(
      (difficulty) => difficulty.name == value,
      orElse: () => SudokuDifficulty.easy,
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.snapshot});

  final OnlineDuelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlayerCard(snapshot: snapshot, seat: OnlineDuelSeat.a),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PlayerCard(snapshot: snapshot, seat: OnlineDuelSeat.b),
        ),
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.snapshot, required this.seat});

  final OnlineDuelSnapshot snapshot;
  final OnlineDuelSeat seat;

  @override
  Widget build(BuildContext context) {
    final player = snapshot.players[seat]!;
    final active = snapshot.currentTurnSeat == seat;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: active ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              player.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
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
  const _TurnBanner({required this.snapshot});

  final OnlineDuelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final text = snapshot.isLocalTurn
        ? context.tr('your_turn')
        : context.tr('opponents_turn');
    return Semantics(
      liveRegion: true,
      child: ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(
          context.tr('online_turn_number', <Object>[snapshot.turnNumber]),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.snapshot});

  final OnlineDuelSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final result = snapshot.winnerSeat == null
        ? context.tr('draw')
        : snapshot.winnerSeat == snapshot.youSeat
        ? context.tr('you_won')
        : context.tr('you_lost');
    final rating = snapshot.rating?[snapshot.youSeat];
    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Icon(Icons.emoji_events_outlined, size: 48),
              const SizedBox(height: 8),
              Text(
                result,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('online_final_score', <Object>[
                  snapshot.scores[OnlineDuelSeat.a] ?? 0,
                  snapshot.scores[OnlineDuelSeat.b] ?? 0,
                ]),
              ),
              if (rating != null)
                Text(
                  context.tr('rating_delta', <Object>[
                    rating.beforeGlobal,
                    rating.afterGlobal,
                    rating.deltaGlobal,
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
