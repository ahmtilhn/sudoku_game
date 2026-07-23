import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/puzzle_catalog.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/sudoku_board.dart';

class DuelScreen extends StatefulWidget {
  const DuelScreen({super.key});

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  static const int turnDuration = 10;
  late final SudokuPuzzle _puzzle;
  late final List<int> _board;
  final List<int> _scores = <int>[0, 0];
  Timer? _timer;
  int? _selectedIndex;
  int? _errorIndex;
  int _currentPlayer = 0;
  int _remainingSeconds = turnDuration;
  int _turn = 1;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _puzzle = PuzzleCatalog.duelPuzzle(
      seed: DateTime.now().millisecondsSinceEpoch,
    );
    _board = List<int>.from(_puzzle.puzzle);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _completed) return;
    if (_remainingSeconds <= 1) {
      _switchTurn(timeout: true);
    } else {
      setState(() => _remainingSeconds--);
    }
  }

  void _selectCell(int index) {
    if (_puzzle.isFixed(index) || _board[index] != 0 || _completed) return;
    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
  }

  void _enterNumber(int value) {
    final index = _selectedIndex;
    if (index == null ||
        _puzzle.isFixed(index) ||
        _board[index] != 0 ||
<<<<<<< HEAD
        _completed)
      return;
=======
        _completed) {
      return;
    }
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
    if (_puzzle.solution[index] == value) {
      HapticFeedback.selectionClick();
      setState(() {
        _board[index] = value;
        _scores[_currentPlayer] += 10;
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _scores[_currentPlayer] -= 5;
        _errorIndex = index;
      });
    }
    if (SudokuEngine.isComplete(_puzzle, _board)) {
      _finishGame();
    } else {
      _switchTurn();
    }
  }

  void _switchTurn({bool timeout = false}) {
    if (!mounted || _completed) return;
    setState(() {
      _currentPlayer = _currentPlayer == 0 ? 1 : 0;
      _remainingSeconds = turnDuration;
      _turn++;
      _selectedIndex = null;
      _errorIndex = null;
    });
    if (timeout) {
      ScaffoldMessenger.of(context).showSnackBar(
<<<<<<< HEAD
        const SnackBar(
          content: Text('Süre doldu. Sıra diğer oyuncuda.'),
          duration: Duration(milliseconds: 850),
=======
        SnackBar(
          content: Text(context.tr('time_up_turn_passed')),
          duration: const Duration(milliseconds: 850),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
        ),
      );
    }
  }

  void _finishGame() {
    _timer?.cancel();
    setState(() => _completed = true);
    final winner = _scores[0] == _scores[1]
        ? null
        : _scores[0] > _scores[1]
<<<<<<< HEAD
        ? 0
        : 1;
=======
            ? 0
            : 1;
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
<<<<<<< HEAD
          winner == null ? 'Berabere!' : 'Oyuncu ${winner + 1} kazandı!',
=======
          winner == null
              ? context.tr('draw')
              : context.tr('player_won', <Object>[winner + 1]),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 58),
            const SizedBox(height: 16),
            Text(
              '${_scores[0]}  —  ${_scores[1]}',
<<<<<<< HEAD
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
=======
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
            ),
            const SizedBox(height: 8),
            Text(context.tr('turns_played', <Object>[_turn])),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: Text(context.tr('main_menu')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('local_duel'))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth > 620
                ? 560.0
                : constraints.maxWidth;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _PlayerScore(
                              player: 1,
                              score: _scores[0],
                              active: _currentPlayer == 0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PlayerScore(
                              player: 2,
                              score: _scores[1],
                              active: _currentPlayer == 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              context.tr('turn', <Object>[_turn]),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 150,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
<<<<<<< HEAD
                                  '$_remainingSeconds saniye',
=======
                                  context.tr(
                                    'seconds',
                                    <Object>[_remainingSeconds],
                                  ),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                  value: _remainingSeconds / turnDuration,
                                  minHeight: 8,
                                  borderRadius: BorderRadius.circular(10),
                                  color: _remainingSeconds <= 3
                                      ? scheme.error
                                      : scheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SudokuBoard(
                        puzzle: _puzzle,
                        board: _board,
                        selectedIndex: _selectedIndex,
                        errorIndex: _errorIndex,
                        enabled: !_completed,
                        onCellTap: _selectCell,
                      ),
                      const SizedBox(height: 18),
                      Text(
<<<<<<< HEAD
                        'Oyuncu ${_currentPlayer + 1}: Bir hücre seç ve tek hamleni yap.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
=======
                        context.tr(
                          'player_instruction',
                          <Object>[_currentPlayer + 1],
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
                      ),
                      const SizedBox(height: 12),
                      NumberPad(
                        maxValue: 9,
                        enabled: !_completed,
                        onNumber: _enterNumber,
                        onErase: () => setState(() => _selectedIndex = null),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlayerScore extends StatelessWidget {
  const _PlayerScore({
    required this.player,
    required this.score,
    required this.active,
  });
<<<<<<< HEAD
=======

>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
  final int player;
  final int score;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? scheme.primary : scheme.outlineVariant,
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(context.tr('player', <Object>[player])),
          const SizedBox(height: 4),
          Text(
            '$score',
<<<<<<< HEAD
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
=======
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
>>>>>>> 8fe6ccd91d5db3ce3d8e23617e404a1b183eb2fe
          ),
        ],
      ),
    );
  }
}
