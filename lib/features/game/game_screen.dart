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

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.puzzle,
    this.onCompleted,
    this.allowNotes = true,
    this.allowHints = true,
    this.completionTitle,
  });

  final SudokuPuzzle puzzle;
  final GameCompleted? onCompleted;
  final bool allowNotes;
  final bool allowHints;
  final String? completionTitle;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late List<int> _board;
  final Map<int, Set<int>> _notes = <int, Set<int>>{};
  final List<_MoveRecord> _history = <_MoveRecord>[];
  Timer? _timer;
  int? _selectedIndex;
  int? _errorIndex;
  int _elapsedSeconds = 0;
  int _mistakes = 0;
  int _hints = 0;
  bool _notesMode = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _board = List<int>.from(widget.puzzle.puzzle);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_completed) setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectCell(int index) {
    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
  }

  void _enterNumber(int value) {
    final index = _selectedIndex;
    if (index == null || widget.puzzle.isFixed(index) || _completed) return;
    if (_notesMode && widget.allowNotes && _board[index] == 0) {
      setState(() {
        final values = _notes.putIfAbsent(index, () => <int>{});
        values.contains(value) ? values.remove(value) : values.add(value);
      });
      return;
    }
    if (widget.puzzle.solution[index] != value) {
      HapticFeedback.heavyImpact();
      setState(() {
        _mistakes++;
        _errorIndex = index;
      });
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (mounted && _errorIndex == index) {
          setState(() => _errorIndex = null);
        }
      });
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _history.add(
        _MoveRecord(
          index: index,
          previousValue: _board[index],
          previousNotes: Set<int>.from(
            _notes[index] ?? const <int>{},
          ),
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
    if (index == null || widget.puzzle.isFixed(index) || _completed) return;
    setState(() {
      _history.add(
        _MoveRecord(
          index: index,
          previousValue: _board[index],
          previousNotes: Set<int>.from(
            _notes[index] ?? const <int>{},
          ),
        ),
      );
      _board[index] = 0;
      _notes.remove(index);
    });
  }

  void _undo() {
    if (_history.isEmpty || _completed) return;
    final move = _history.removeLast();
    setState(() {
      _board[move.index] = move.previousValue;
      move.previousNotes.isEmpty
          ? _notes.remove(move.index)
          : _notes[move.index] = Set<int>.from(move.previousNotes);
      _selectedIndex = move.index;
    });
  }

  void _hint() {
    if (!widget.allowHints || _completed) return;
    var candidate = _selectedIndex;
    if (candidate == null ||
        widget.puzzle.isFixed(candidate) ||
        _board[candidate] != 0) {
      candidate = _board.indexOf(0);
    }
    if (candidate < 0) return;
    final index = candidate;
    setState(() {
      _history.add(
        _MoveRecord(
          index: index,
          previousValue: _board[index],
          previousNotes: Set<int>.from(
            _notes[index] ?? const <int>{},
          ),
        ),
      );
      _selectedIndex = index;
      _board[index] = widget.puzzle.solution[index];
      _notes.remove(index);
      _hints++;
    });
    _checkCompletion();
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
      mistakes: _mistakes,
      hints: _hints,
    );
    if (!mounted) return;
    final stars = _mistakes == 0 && _hints == 0
        ? 3
        : _mistakes <= 2 && _hints <= 1
            ? 2
            : 1;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          widget.completionTitle ?? context.tr('congratulations'),
        ),
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
              value: '$_mistakes',
            ),
            _ResultRow(
              label: context.tr('hints'),
              value: '$_hints',
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop(true);
            },
            child: Text(context.tr('continue')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                          Chip(
                            avatar: const Icon(
                              Icons.error_outline,
                              size: 18,
                            ),
                            label: Text(
                              context.tr(
                                'mistakes_count',
                                <Object>[_mistakes],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            avatar: const Icon(
                              Icons.lightbulb_outline,
                              size: 18,
                            ),
                            label: Text(
                              context.tr(
                                'hints_count',
                                <Object>[_hints],
                              ),
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
                        enabled: !_completed,
                        onCellTap: _selectCell,
                      ),
                      const SizedBox(height: 18),
                      NumberPad(
                        maxValue: widget.puzzle.size,
                        enabled: !_completed,
                        notesEnabled: _notesMode,
                        onNumber: _enterNumber,
                        onErase: _erase,
                        onToggleNotes: widget.allowNotes
                            ? () => setState(
                                  () => _notesMode = !_notesMode,
                                )
                            : null,
                        onUndo: _history.isEmpty ? null : _undo,
                        onHint: widget.allowHints ? _hint : null,
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
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
