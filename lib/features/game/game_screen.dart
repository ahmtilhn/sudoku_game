import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../data/game_session_store.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/sudoku_board.dart';

typedef GameCompleted =
    Future<void> Function({
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

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final GameSessionStore _sessionStore = GameSessionStore.instance;
  final Stopwatch _stopwatch = Stopwatch();
  late List<int> _board;
  final Map<int, Set<int>> _notes = <int, Set<int>>{};
  final List<_MoveRecord> _history = <_MoveRecord>[];
  final Set<int> _hintedIndexes = <int>{};
  Timer? _timer;
  Timer? _saveDebounce;
  int? _selectedIndex;
  int? _errorIndex;
  int _elapsedBaseSeconds = 0;
  int _elapsedSeconds = 0;
  int _mistakes = 0;
  int _totalMistakes = 0;
  int _hintsUsed = 0;
  bool _notesMode = false;
  bool _completed = false;
  bool _roundLost = false;
  bool _lossDialogVisible = false;
  bool _hintInProgress = false;
  bool _sessionReady = false;

  bool get _canUndo =>
      _history.isNotEmpty && !_completed && !_roundLost && _sessionReady;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _board = List<int>.from(widget.puzzle.puzzle);
    unawaited(_initializeSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      return;
    }
    _pauseClock();
    unawaited(_saveNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseClock();
    _saveDebounce?.cancel();
    if (!_completed && _sessionReady) unawaited(_saveNow());
    super.dispose();
  }

  Future<void> _initializeSession() async {
    final saved = await _sessionStore.load(widget.puzzle);
    if (!mounted) return;
    if (saved != null) {
      _board = List<int>.from(saved.board);
      _notes
        ..clear()
        ..addAll(
          saved.notes.map(
            (index, values) => MapEntry(index, Set<int>.from(values)),
          ),
        );
      _history
        ..clear()
        ..addAll(
          saved.history.map(
            (move) => _MoveRecord(
              index: move.index,
              previousValue: move.previousValue,
              previousNotes: Set<int>.from(move.previousNotes),
            ),
          ),
        );
      _hintedIndexes
        ..clear()
        ..addAll(saved.hintedIndexes);
      _selectedIndex = saved.selectedIndex;
      _elapsedBaseSeconds = saved.elapsedSeconds;
      _elapsedSeconds = saved.elapsedSeconds;
      _mistakes = saved.mistakes;
      _totalMistakes = saved.totalMistakes;
      _hintsUsed = saved.hintsUsed;
      _notesMode = saved.notesMode && widget.allowNotes;
      _roundLost = saved.roundLost;
    }
    setState(() => _sessionReady = true);
    if (_roundLost) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showRoundLostDialog());
      });
    } else {
      _startClock();
    }
  }

  void _startClock() {
    if (!_sessionReady || _completed || _roundLost || _stopwatch.isRunning) {
      return;
    }
    _stopwatch.start();
    _timer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_stopwatch.isRunning) return;
      final current = _elapsedBaseSeconds + _stopwatch.elapsed.inSeconds;
      if (current == _elapsedSeconds) return;
      setState(() => _elapsedSeconds = current);
      if (current % 5 == 0) _scheduleSave();
    });
  }

  void _pauseClock() {
    if (_stopwatch.isRunning) {
      _elapsedBaseSeconds += _stopwatch.elapsed.inSeconds;
      _stopwatch
        ..stop()
        ..reset();
      _elapsedSeconds = _elapsedBaseSeconds;
    }
    _timer?.cancel();
    _timer = null;
  }

  void _selectCell(int index) {
    if (_roundLost || !_sessionReady) return;
    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
    _scheduleSave();
  }

  void _enterNumber(int value) {
    final index = _selectedIndex;
    if (index == null ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index) ||
        _completed ||
        _roundLost ||
        !_sessionReady) {
      return;
    }

    if (_notesMode && widget.allowNotes && _board[index] == 0) {
      setState(() {
        final values = _notes.putIfAbsent(index, () => <int>{});
        values.contains(value) ? values.remove(value) : values.add(value);
        if (values.isEmpty) _notes.remove(index);
      });
      _scheduleSave();
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
      _scheduleSave();

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
    _scheduleSave();
    unawaited(_checkCompletion());
  }

  void _erase() {
    final index = _selectedIndex;
    if (index == null ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index) ||
        _completed ||
        _roundLost ||
        !_sessionReady) {
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
    _scheduleSave();
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
    _scheduleSave();
  }

  void _toggleNotes() {
    if (!_sessionReady || _completed || _roundLost) return;
    setState(() => _notesMode = !_notesMode);
    _scheduleSave();
  }

  Future<void> _hint() async {
    if (!widget.allowHints ||
        _completed ||
        _roundLost ||
        _hintInProgress ||
        !_sessionReady) {
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
      _scheduleSave();
      await _checkCompletion();
    } finally {
      if (mounted) {
        setState(() => _hintInProgress = false);
      }
    }
  }

  Future<void> _showRoundLostDialog() async {
    if (!mounted || _lossDialogVisible || _completed) return;
    _pauseClock();
    setState(() {
      _roundLost = true;
      _lossDialogVisible = true;
    });
    await _saveNow();
    if (!mounted) return;

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
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_LossAction.coin),
              icon: const Icon(Icons.monetization_on_outlined),
              label: Text(
                context.tr('continue_with_coins', <Object>[
                  widget.coinContinueCost,
                ]),
              ),
            ),
          if (widget.onRewardedContinue != null && !AdsService.instance.noAds)
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('not_enough_coins'))));
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
    _startClock();
    _scheduleSave(immediate: true);
  }

  void _restartPuzzle() {
    _pauseClock();
    setState(() {
      _board = List<int>.from(widget.puzzle.puzzle);
      _notes.clear();
      _history.clear();
      _hintedIndexes.clear();
      _selectedIndex = null;
      _errorIndex = null;
      _elapsedBaseSeconds = 0;
      _elapsedSeconds = 0;
      _mistakes = 0;
      _totalMistakes = 0;
      _hintsUsed = 0;
      _notesMode = false;
      _roundLost = false;
      _hintInProgress = false;
    });
    _startClock();
    _scheduleSave(immediate: true);
  }

  void _removeRelatedNotes(int index, int value) {
    final row = index ~/ widget.puzzle.size;
    final column = index % widget.puzzle.size;
    final box = SudokuEngine.relatedBoxIndex(widget.puzzle, index);
    final emptyEntries = <int>[];
    for (final entry in _notes.entries) {
      final noteIndex = entry.key;
      if (noteIndex ~/ widget.puzzle.size == row ||
          noteIndex % widget.puzzle.size == column ||
          SudokuEngine.relatedBoxIndex(widget.puzzle, noteIndex) == box) {
        entry.value.remove(value);
        if (entry.value.isEmpty) emptyEntries.add(noteIndex);
      }
    }
    for (final index in emptyEntries) {
      _notes.remove(index);
    }
  }

  Future<void> _checkCompletion() async {
    if (!SudokuEngine.isComplete(widget.puzzle, _board)) return;
    _pauseClock();
    setState(() => _completed = true);
    _saveDebounce?.cancel();
    await _sessionStore.delete(widget.puzzle.id);
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
            _ResultRow(label: context.tr('mistakes'), value: '$_totalMistakes'),
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

  void _scheduleSave({bool immediate = false}) {
    if (!_sessionReady || _completed) return;
    _saveDebounce?.cancel();
    if (immediate) {
      unawaited(_saveNow());
      return;
    }
    _saveDebounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_saveNow()),
    );
  }

  Future<void> _saveNow() async {
    if (!_sessionReady || _completed) return;
    final elapsed = _elapsedBaseSeconds + _stopwatch.elapsed.inSeconds;
    await _sessionStore.save(
      GameSessionSnapshot(
        puzzleId: widget.puzzle.id,
        puzzleSignature: GameSessionSnapshot.signatureFor(widget.puzzle),
        board: List<int>.from(_board),
        notes: _notes.map(
          (index, values) => MapEntry(index, Set<int>.from(values)),
        ),
        history: _history
            .map(
              (move) => GameSessionMove(
                index: move.index,
                previousValue: move.previousValue,
                previousNotes: Set<int>.from(move.previousNotes),
              ),
            )
            .toList(),
        hintedIndexes: Set<int>.from(_hintedIndexes),
        selectedIndex: _selectedIndex,
        elapsedSeconds: elapsed,
        mistakes: _mistakes,
        totalMistakes: _totalMistakes,
        hintsUsed: _hintsUsed,
        notesMode: _notesMode,
        roundLost: _roundLost,
        savedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = _sessionReady && !_completed && !_roundLost;
    final availableHints = widget.hintBalanceProvider?.call();
    final mistakeLabel = widget.mistakeLimit == null
        ? context.tr('mistakes_count', <Object>[_mistakes])
        : context.tr('mistakes_limit_count', <Object>[
            _mistakes,
            widget.mistakeLimit!,
          ]);

    return Scaffold(
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
          onToggleNotes: widget.allowNotes ? _toggleNotes : null,
          onUndo: _canUndo ? _undo : null,
          onHint: widget.allowHints ? _hint : null,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth > 760
                ? 700.0
                : constraints.maxWidth;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      if (!_sessionReady) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ],
                      InPageHeader(
                        title: context.strings.puzzleTitle(widget.puzzle),
                        actions: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              formatDuration(_elapsedSeconds),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
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
