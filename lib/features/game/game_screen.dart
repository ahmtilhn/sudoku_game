import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/sudoku_board.dart';

typedef GameCompleted = Future<void> Function({
  required int seconds,
  required int mistakes,
  required int hints,
});

typedef CoinContinue = Future<bool> Function(int cost);
typedef RewardedContinue = Future<bool> Function();
typedef HintConsumer = Future<bool> Function();

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.puzzle,
    this.onCompleted,
    this.allowNotes = true,
    this.allowHints = true,
    this.completionTitle,
    this.mistakeLimit,
    this.coinContinueCost = 25,
    this.onCoinContinue,
    this.onRewardedContinue,
    this.onConsumeHint,
    this.hintBalanceProvider,
  });

  final SudokuPuzzle puzzle;
  final GameCompleted? onCompleted;
  final bool allowNotes;
  final bool allowHints;
  final String? completionTitle;
  final int? mistakeLimit;
  final int coinContinueCost;
  final CoinContinue? onCoinContinue;
  final RewardedContinue? onRewardedContinue;
  final HintConsumer? onConsumeHint;
  final int Function()? hintBalanceProvider;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late List<int> _board;
  final Map<int, Set<int>> _notes = <int, Set<int>>{};
  final List<_MoveRecord> _history = <_MoveRecord>[];
  final Set<int> _hintedIndexes = <int>{};
  Timer? _timer;
  int? _selectedIndex;
  int? _errorIndex;
  int _elapsedSeconds = 0;
  int _mistakes = 0;
  int _totalMistakes = 0;
  int _hintsUsed = 0;
  bool _notesMode = false;
  bool _completed = false;
  bool _roundLost = false;
  bool _lossDialogVisible = false;
  bool _hintInProgress = false;

  bool get _canUndo => _history.isNotEmpty && !_completed && !_roundLost;

  @override
  void initState() {
    super.initState();
    _board = List<int>.from(widget.puzzle.puzzle);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_completed && !_roundLost) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectCell(int index) {
    if (_roundLost) return;
    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
  }

  void _enterNumber(int value) {
    final index = _selectedIndex;
    if (index == null ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index) ||
        _completed ||
        _roundLost) {
      return;
    }

    if (_notesMode && widget.allowNotes && _board[index] == 0) {
      setState(() {
        final values = _notes.putIfAbsent(index, () => <int>{});
        values.contains(value) ? values.remove(value) : values.add(value);
      });
      return;
    }

    if (widget.puzzle.solution[index] != value) {
      HapticFeedback.heavyImpact();
      final nextMistakes = _mistakes + 1;
      setState(() {
        _mistakes = nextMistakes;
        _totalMistakes++;
        _errorIndex = index;
      });

      final limit = widget.mistakeLimit;
      if (limit != null && nextMistakes >= limit) {
        Future<void>.microtask(_showRoundLostDialog);
      } else {
        Future<void>.delayed(const Duration(milliseconds: 650), () {
          if (mounted && _errorIndex == index) {
            setState(() => _errorIndex = null);
          }
        });
      }
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _history.add(
        _MoveRecord(
          index: index,
          previousValue: _board[index],
          previousNotes: Set<int>.from(_notes[index] ?? const <int>{}),
        ),
      );
      _board[index] = value;
      _notes.remove(index);
      _removeRelatedNotes(index, value);
    });
    _checkCompletion();
  }

  void _erase() {
    final index = _selectedIndex;
    if (index == null ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index) ||
        _completed ||
        _roundLost) {
      return;
    }
    setState(() {
      _history.add(
        _MoveRecord(
          index: index,
          previousValue: _board[index],
          previousNotes: Set<int>.from(_notes[index] ?? const <int>{}),
        ),
      );
      _board[index] = 0;
      _notes.remove(index);
    });
  }

  void _undo() {
    if (!_canUndo) return;
    final move = _history.removeLast();
    setState(() {
      _board[move.index] = move.previousValue;
      move.previousNotes.isEmpty
          ? _notes.remove(move.index)
          : _notes[move.index] = Set<int>.from(move.previousNotes);
      _selectedIndex = move.index;
    });
  }

  Future<void> _hint() async {
    if (!widget.allowHints ||
        _completed ||
        _roundLost ||
        _hintInProgress) {
      return;
    }

    var candidate = _selectedIndex ?? -1;
    if (candidate < 0 ||
        widget.puzzle.isFixed(candidate) ||
        _hintedIndexes.contains(candidate) ||
        _board[candidate] != 0) {
      candidate = _board.indexOf(0);
    }
    if (candidate < 0) return;

    setState(() => _hintInProgress = true);
    try {
      final consumeHint = widget.onConsumeHint;
      if (consumeHint != null) {
        final allowed = await consumeHint();
        if (!mounted || !allowed) return;
      }

      if (_board[candidate] != 0 ||
          widget.puzzle.isFixed(candidate) ||
          _hintedIndexes.contains(candidate)) {
        candidate = _board.indexOf(0);
      }
      if (!mounted || candidate < 0) return;

      final index = candidate;
      setState(() {
        _selectedIndex = index;
        _board[index] = widget.puzzle.solution[index];
        _hintedIndexes.add(index);
        _notes.remove(index);
        _removeRelatedNotes(index, _board[index]);
        _hintsUsed++;
      });
      _checkCompletion();
    } finally {
      if (mounted) {
        setState(() => _hintInProgress = false);
      }
    }
  }

  Future<void> _showRoundLostDialog() async {
    if (!mounted || _lossDialogVisible || _completed) return;
    setState(() {
      _roundLost = true;
      _lossDialogVisible = true;
    });

    final action = await showDialog<_LossAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('round_lost')),
        content: Text(
          context.tr('mistake_limit_reached', <Object>[
            widget.mistakeLimit ?? 3,
          ]),
        ),
        actions: [
          if (widget.onCoinContinue != null)
            TextButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(_LossAction.coin),
              icon: const Icon(Icons.monetization_on_outlined),
              label: Text(
                context.tr('continue_with_coins', <Object>[
                  widget.coinContinueCost,
                ]),
              ),
            ),
          if (widget.onRewardedContinue != null)
            TextButton.icon(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_LossAction.rewardedAd),
              icon: const Icon(Icons.ondemand_video_outlined),
              label: Text(context.tr('watch_rewarded_ad')),
            ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LossAction.restart),
            icon: const Icon(Icons.restart_alt),
            label: Text(context.tr('restart_puzzle')),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() => _lossDialogVisible = false);

    if (action == _LossAction.coin) {
      final continued =
          await widget.onCoinContinue?.call(widget.coinContinueCost) ?? false;
      if (!mounted) return;
      if (continued) {
        _resumeAfterLoss();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('not_enough_coins'))),
        );
        await _showRoundLostDialog();
      }
      return;
    }

    if (action == _LossAction.rewardedAd) {
      final continued = await widget.onRewardedContinue?.call() ?? false;
      if (!mounted) return;
      if (continued) {
        _resumeAfterLoss();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('rewarded_ad_unavailable'))),
        );
        await _showRoundLostDialog();
      }
      return;
    }

    if (action == _LossAction.restart) {
      _restartPuzzle();
      return;
    }

    await _showRoundLostDialog();
  }

  void _resumeAfterLoss() {
    setState(() {
      _mistakes = 0;
      _errorIndex = null;
      _roundLost = false;
    });
  }

  void _restartPuzzle() {
    setState(() {
      _board = List<int>.from(widget.puzzle.puzzle);
      _notes.clear();
      _history.clear();
      _hintedIndexes.clear();
      _selectedIndex = null;
      _errorIndex = null;
      _elapsedSeconds = 0;
      _mistakes = 0;
      _totalMistakes = 0;
      _hintsUsed = 0;
      _notesMode = false;
      _roundLost = false;
      _hintInProgress = false;
    });
  }

  void _removeRelatedNotes(int index, int value) {
    final row = index ~/ widget.puzzle.size;
    final column = index % widget.puzzle.size;
    final box = SudokuEngine.relatedBoxIndex(widget.puzzle, index);
    for (final entry in _notes.entries) {
      final noteIndex = entry.key;
      if (noteIndex ~/ widget.puzzle.size == row ||
          noteIndex % widget.puzzle.size == column ||
          SudokuEngine.relatedBoxIndex(widget.puzzle, noteIndex) == box) {
        entry.value.remove(value);
      }
    }
  }

  Future<void> _checkCompletion() async {
    if (!SudokuEngine.isComplete(widget.puzzle, _board)) return;
    _timer?.cancel();
    setState(() => _completed = true);
    await widget.onCompleted?.call(
      seconds: _elapsedSeconds,
      mistakes: _totalMistakes,
      hints: _hintsUsed,
    );
    if (!mounted) return;

    final stars = _totalMistakes == 0 && _hintsUsed == 0
        ? 3
        : _totalMistakes <= 2 && _hintsUsed <= 1
            ? 2
            : 1;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.completionTitle ?? context.tr('congratulations')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                3,
                (index) => Icon(
                  index < stars
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 42,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ResultRow(
              label: context.tr('time'),
              value: formatDuration(_elapsedSeconds),
            ),
            _ResultRow(
              label: context.tr('mistakes'),
              value: '$_totalMistakes',
            ),
            _ResultRow(label: context.tr('hints'), value: '$_hintsUsed'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop(true);
            },
            child: Text(context.tr('continue_action')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = !_completed && !_roundLost;
    final availableHints = widget.hintBalanceProvider?.call();
    final mistakeLabel = widget.mistakeLimit == null
        ? context.tr('mistakes_count', <Object>[_mistakes])
        : context.tr('mistakes_limit_count', <Object>[
            _mistakes,
            widget.mistakeLimit!,
          ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.strings.puzzleTitle(widget.puzzle)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                formatDuration(_elapsedSeconds),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NumberPadDock(
        child: NumberPad(
          maxValue: widget.puzzle.size,
          completedValues: completedSudokuNumbers(
            board: _board,
            maxValue: widget.puzzle.size,
          ),
          enabled: controlsEnabled,
          notesEnabled: _notesMode,
          hintCount: availableHints,
          onNumber: _enterNumber,
          onErase: _erase,
          onToggleNotes: widget.allowNotes
              ? () => setState(() => _notesMode = !_notesMode)
              : null,
          onUndo: _canUndo ? _undo : null,
          onHint: widget.allowHints ? _hint : null,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth > 620
                ? 560.0
                : constraints.maxWidth;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Chip(
                            avatar: const Icon(Icons.error_outline, size: 18),
                            label: Text(mistakeLabel),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            avatar: const Icon(
                              Icons.lightbulb_outline,
                              size: 18,
                            ),
                            label: Text(
                              context.tr('hints_count', <Object>[
                                availableHints ?? _hintsUsed,
                              ]),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            context.strings.difficultyLabel(
                              widget.puzzle.difficulty,
                            ),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SudokuBoard(
                        puzzle: widget.puzzle,
                        board: _board,
                        selectedIndex: _selectedIndex,
                        notes: _notes,
                        errorIndex: _errorIndex,
                        hintedIndexes: _hintedIndexes,
                        enabled: controlsEnabled,
                        onCellTap: _selectCell,
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

enum _LossAction { coin, rewardedAd, restart }

class _MoveRecord {
  const _MoveRecord({
    required this.index,
    required this.previousValue,
    required this.previousNotes,
  });

  final int index;
  final int previousValue;
  final Set<int> previousNotes;
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
