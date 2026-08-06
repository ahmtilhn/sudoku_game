import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../data/local_progress_store.dart';
import '../../data/ux_game_session_store.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../localization/ux_copy.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/sudoku_board.dart';
import '../../widgets/ux_feedback.dart';
import 'hint_economy.dart';

typedef EnhancedGameCompleted = Future<void> Function({
  required int seconds,
  required int mistakes,
  required int hints,
});

enum EnhancedGameExit { next, menu }

enum _PauseAction { resume, restart, menu }
enum _LossAction { coin, rewarded, restart, exit }
enum _ResultAction { next, restart, menu }

class EnhancedGameScreen extends StatefulWidget {
  const EnhancedGameScreen({
    super.key,
    required this.puzzle,
    required this.store,
    this.onCompleted,
    this.completionTitle,
    this.mistakeLimit = 3,
    this.allowNotes = true,
    this.allowHints = true,
    this.showNextAction = true,
  });

  final SudokuPuzzle puzzle;
  final LocalProgressStore store;
  final EnhancedGameCompleted? onCompleted;
  final String? completionTitle;
  final int? mistakeLimit;
  final bool allowNotes;
  final bool allowHints;
  final bool showNextAction;

  @override
  State<EnhancedGameScreen> createState() => _EnhancedGameScreenState();
}

class _EnhancedGameScreenState extends State<EnhancedGameScreen>
    with WidgetsBindingObserver {
  static const int _continueCost = 25;

  final UxGameSessionStore _sessions = UxGameSessionStore.instance;
  final Stopwatch _stopwatch = Stopwatch();
  final TransformationController _boardTransform = TransformationController();
  final Map<int, Set<int>> _notes = <int, Set<int>>{};
  final List<UxSessionMove> _history = <UxSessionMove>[];
  final Set<int> _hintedIndexes = <int>{};

  late List<int> _board;
  Timer? _clockTimer;
  Timer? _saveDebounce;
  int? _selectedIndex;
  int? _errorIndex;
  int _elapsedBaseSeconds = 0;
  int _elapsedSeconds = 0;
  int _mistakes = 0;
  int _totalMistakes = 0;
  int _hintsUsed = 0;
  bool _notesMode = false;
  bool _ready = false;
  bool _completed = false;
  bool _roundLost = false;
  bool _lossVisible = false;
  bool _hintBusy = false;
  bool _paused = false;
  bool _pauseVisible = false;
  bool _allowExit = false;

  bool get _inputEnabled =>
      _ready && !_completed && !_roundLost && !_paused;

  bool get _canUndo => _inputEnabled && _history.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _board = List<int>.from(widget.puzzle.puzzle);
    unawaited(_restore());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_paused && !_pauseVisible && _ready && !_completed && !_roundLost) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_showPauseMenu());
        });
      } else if (!_paused) {
        _startClock();
      }
      return;
    }
    _pauseClock();
    if (mounted && _ready && !_completed && !_roundLost && !_paused) {
      setState(() => _paused = true);
    }
    unawaited(_saveNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseClock();
    _saveDebounce?.cancel();
    _boardTransform.dispose();
    if (_ready && !_completed) unawaited(_saveNow());
    super.dispose();
  }

  Future<void> _restore() async {
    final saved = await _sessions.load(widget.puzzle);
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
        ..addAll(saved.history);
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
    setState(() => _ready = true);
    if (_roundLost) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showLossSheet());
      });
    } else {
      _startClock();
    }
  }

  void _startClock() {
    if (!_ready ||
        _completed ||
        _roundLost ||
        _paused ||
        _stopwatch.isRunning) {
      return;
    }
    _stopwatch.start();
    _clockTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_stopwatch.isRunning) return;
      final seconds = _elapsedBaseSeconds + _stopwatch.elapsed.inSeconds;
      if (seconds == _elapsedSeconds) return;
      setState(() => _elapsedSeconds = seconds);
      if (seconds % 5 == 0) _scheduleSave();
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
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  void _fitBoard() {
    _boardTransform.value = Matrix4.identity();
  }

  Future<void> _showPauseMenu() async {
    if (!mounted ||
        !_ready ||
        _completed ||
        _roundLost ||
        _pauseVisible) {
      return;
    }
    _pauseClock();
    setState(() {
      _paused = true;
      _pauseVisible = true;
    });
    await _saveNow();
    if (!mounted) return;

    final action = await showAdaptiveBottomSheet<_PauseAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => UxOutcomeSheet(
        icon: Icons.pause_circle_filled_rounded,
        title: UxCopy.pausedTitle(sheetContext),
        subtitle: UxCopy.pausedBody(sheetContext),
        metrics: <Widget>[
          UxMetricTile(
            label: sheetContext.tr('time'),
            value: formatDuration(_elapsedSeconds),
            icon: Icons.timer_outlined,
          ),
          UxMetricTile(
            label: sheetContext.tr('mistakes'),
            value: '$_mistakes${widget.mistakeLimit == null ? '' : '/${widget.mistakeLimit}'}',
            icon: Icons.error_outline_rounded,
          ),
        ],
        primaryLabel: sheetContext.tr('continue_action'),
        onPrimary: () =>
            Navigator.of(sheetContext).pop(_PauseAction.resume),
        secondaryLabel: sheetContext.tr('restart_puzzle'),
        onSecondary: () =>
            Navigator.of(sheetContext).pop(_PauseAction.restart),
        tertiaryLabel: sheetContext.tr('main_menu'),
        onTertiary: () => Navigator.of(sheetContext).pop(_PauseAction.menu),
      ),
    );

    if (!mounted) return;
    setState(() => _pauseVisible = false);

    if (action == _PauseAction.resume) {
      setState(() => _paused = false);
      _startClock();
      return;
    }
    if (action == _PauseAction.restart) {
      final confirmed = await _confirmRestart();
      if (!mounted) return;
      if (confirmed) {
        _restartPuzzle();
      } else {
        unawaited(_showPauseMenu());
      }
      return;
    }
    await _exitToMenu();
  }

  Future<bool> _confirmRestart() {
    return GameModal.warning(
      context,
      title: UxCopy.restartTitle(context),
      message: UxCopy.restartBody(context),
      confirmLabel: context.tr('restart_puzzle'),
      cancelLabel: context.tr('cancel'),
    );
  }

  Future<void> _exitToMenu() async {
    _pauseClock();
    await _saveNow();
    if (!mounted) return;
    setState(() => _allowExit = true);
    Navigator.of(context).pop(EnhancedGameExit.menu);
  }

  void _selectCell(int index) {
    if (!_inputEnabled) return;
    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
    _scheduleSave();
  }

  void _enterNumber(int value) {
    final index = _selectedIndex;
    if (index == null ||
        !_inputEnabled ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index)) {
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
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _mistakes++;
        _totalMistakes++;
        _errorIndex = index;
      });
      _scheduleSave();
      if (widget.mistakeLimit != null && _mistakes >= widget.mistakeLimit!) {
        Future<void>.microtask(_showLossSheet);
      } else {
        Future<void>.delayed(const Duration(milliseconds: 650), () {
          if (mounted && _errorIndex == index) {
            setState(() => _errorIndex = null);
          }
        });
      }
      return;
    }

    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _history.add(
        UxSessionMove(
          index: index,
          previousValue: _board[index],
          previousNotes: Set<int>.from(_notes[index] ?? const <int>{}),
        ),
      );
      _board[index] = value;
      _notes.remove(index);
      _removeRelatedNotes(index, value);
      _errorIndex = null;
    });
    _scheduleSave();
    unawaited(_checkCompletion());
  }

  void _erase() {
    final index = _selectedIndex;
    if (index == null ||
        !_inputEnabled ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index)) {
      return;
    }
    setState(() {
      _history.add(
        UxSessionMove(
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
      if (move.previousNotes.isEmpty) {
        _notes.remove(move.index);
      } else {
        _notes[move.index] = Set<int>.from(move.previousNotes);
      }
      _selectedIndex = move.index;
      _errorIndex = null;
    });
    _scheduleSave();
  }

  void _toggleNotes() {
    if (!_inputEnabled) return;
    setState(() => _notesMode = !_notesMode);
    _scheduleSave();
  }

  Future<void> _hint() async {
    if (!widget.allowHints || !_inputEnabled || _hintBusy) return;
    var index = _selectedIndex ?? -1;
    if (index < 0 ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index) ||
        _board[index] != 0) {
      index = _board.indexOf(0);
    }
    if (index < 0) return;

    setState(() => _hintBusy = true);
    try {
      final allowed = await HintEconomy.consumeOrAcquire(context, widget.store);
      if (!mounted || !allowed) return;
      if (_board[index] != 0) index = _board.indexOf(0);
      if (index < 0) return;
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
      if (mounted) setState(() => _hintBusy = false);
    }
  }

  Future<void> _showLossSheet() async {
    if (!mounted || _lossVisible || _completed) return;
    _pauseClock();
    setState(() {
      _roundLost = true;
      _lossVisible = true;
    });
    await _saveNow();
    if (!mounted) return;

    final action = await showAdaptiveBottomSheet<_LossAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => UxOutcomeSheet(
        icon: Icons.flag_rounded,
        title: sheetContext.tr('round_lost'),
        subtitle: sheetContext.tr('mistake_limit_reached', <Object>[
          widget.mistakeLimit ?? 3,
        ]),
        accent: Theme.of(sheetContext).colorScheme.error,
        metrics: <Widget>[
          UxMetricTile(
            label: sheetContext.tr('time'),
            value: formatDuration(_elapsedSeconds),
            icon: Icons.timer_outlined,
          ),
          UxMetricTile(
            label: sheetContext.tr('mistakes'),
            value: '$_totalMistakes',
            icon: Icons.error_outline_rounded,
          ),
        ],
        primaryLabel: sheetContext.tr(
          'continue_with_coins',
          const <Object>[_continueCost],
        ),
        onPrimary: () => Navigator.of(sheetContext).pop(_LossAction.coin),
        secondaryLabel: AdsService.instance.noAds
            ? sheetContext.tr('restart_puzzle')
            : sheetContext.tr('watch_rewarded_ad'),
        onSecondary: () => Navigator.of(sheetContext).pop(
          AdsService.instance.noAds
              ? _LossAction.restart
              : _LossAction.rewarded,
        ),
        tertiaryLabel: sheetContext.tr('main_menu'),
        onTertiary: () => Navigator.of(sheetContext).pop(_LossAction.exit),
      ),
    );

    if (!mounted) return;
    setState(() => _lossVisible = false);

    if (action == _LossAction.coin) {
      final continued = await EconomyService.instance.spendCareerContinue();
      if (!mounted) return;
      if (continued) {
        _resumeAfterLoss();
      } else {
        await GameModal.error(
          context,
          title: context.tr('round_lost'),
          message: context.tr('not_enough_coins'),
          retryLabel: context.tr('try_again'),
          cancelLabel: context.tr('cancel'),
        );
        await _showLossSheet();
      }
      return;
    }
    if (action == _LossAction.rewarded) {
      final continued = await AdsService.instance.showRewarded();
      if (!mounted) return;
      if (continued) {
        _resumeAfterLoss();
      } else {
        await GameModal.error(
          context,
          title: context.tr('round_lost'),
          message: context.tr('rewarded_ad_unavailable'),
          retryLabel: context.tr('try_again'),
          cancelLabel: context.tr('cancel'),
        );
        await _showLossSheet();
      }
      return;
    }
    if (action == _LossAction.restart) {
      _restartPuzzle();
      return;
    }
    await _exitToMenu();
  }

  void _resumeAfterLoss() {
    setState(() {
      _mistakes = 0;
      _roundLost = false;
      _errorIndex = null;
      _paused = false;
    });
    _startClock();
    _scheduleSave(immediate: true);
  }

  void _restartPuzzle() {
    _pauseClock();
    _fitBoard();
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
      _completed = false;
      _roundLost = false;
      _paused = false;
    });
    _startClock();
    _scheduleSave(immediate: true);
  }

  void _removeRelatedNotes(int index, int value) {
    final row = index ~/ widget.puzzle.size;
    final column = index % widget.puzzle.size;
    final box = SudokuEngine.relatedBoxIndex(widget.puzzle, index);
    final empty = <int>[];
    for (final entry in _notes.entries) {
      final noteIndex = entry.key;
      if (noteIndex ~/ widget.puzzle.size == row ||
          noteIndex % widget.puzzle.size == column ||
          SudokuEngine.relatedBoxIndex(widget.puzzle, noteIndex) == box) {
        entry.value.remove(value);
        if (entry.value.isEmpty) empty.add(noteIndex);
      }
    }
    for (final noteIndex in empty) {
      _notes.remove(noteIndex);
    }
  }

  Future<void> _checkCompletion() async {
    if (_completed || !SudokuEngine.isComplete(widget.puzzle, _board)) return;
    _pauseClock();
    setState(() => _completed = true);
    _saveDebounce?.cancel();
    await _sessions.clear();
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
    final action = await showAdaptiveBottomSheet<_ResultAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => _GameResultSheet(
        title: widget.completionTitle ?? sheetContext.tr('congratulations'),
        stars: stars,
        seconds: _elapsedSeconds,
        mistakes: _totalMistakes,
        hints: _hintsUsed,
        showNextAction: widget.showNextAction,
      ),
    );
    if (!mounted) return;
    if (action == _ResultAction.restart) {
      _restartPuzzle();
      return;
    }
    setState(() => _allowExit = true);
    Navigator.of(context).pop(
      action == _ResultAction.next
          ? EnhancedGameExit.next
          : EnhancedGameExit.menu,
    );
  }

  void _scheduleSave({bool immediate = false}) {
    if (!_ready || _completed) return;
    _saveDebounce?.cancel();
    if (immediate) {
      unawaited(_saveNow());
    } else {
      _saveDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_saveNow()),
      );
    }
  }

  Future<void> _saveNow() async {
    if (!_ready || _completed) return;
    final elapsed = _elapsedBaseSeconds + _stopwatch.elapsed.inSeconds;
    await _sessions.save(
      UxGameSession(
        puzzle: widget.puzzle,
        board: List<int>.from(_board),
        notes: _notes.map(
          (index, values) => MapEntry(index, Set<int>.from(values)),
        ),
        history: List<UxSessionMove>.from(_history),
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
    final mistakeLabel = widget.mistakeLimit == null
        ? context.tr('mistakes_count', <Object>[_mistakes])
        : context.tr('mistakes_limit_count', <Object>[
            _mistakes,
            widget.mistakeLimit!,
          ]);

    return PopScope<EnhancedGameExit>(
      canPop: _allowExit || _completed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_showPauseMenu());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.strings.puzzleTitle(widget.puzzle)),
          actions: [
            Semantics(
              label: context.tr('time'),
              child: Center(
                child: Text(
                  formatDuration(_elapsedSeconds),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey<String>('action-pause'),
              tooltip: UxCopy.pause(context),
              onPressed: _inputEnabled ? _showPauseMenu : null,
              icon: const Icon(Icons.pause_circle_outline_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        bottomNavigationBar: NumberPadDock(
          child: NumberPad(
            maxValue: widget.puzzle.size,
            completedValues: completedSudokuNumbers(
              board: _board,
              maxValue: widget.puzzle.size,
            ),
            enabled: _inputEnabled,
            notesEnabled: _notesMode,
            hintCount: widget.store.hints,
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
              final boardWidget = SudokuBoard(
                puzzle: widget.puzzle,
                board: _board,
                selectedIndex: _selectedIndex,
                notes: _notes,
                errorIndex: _errorIndex,
                hintedIndexes: _hintedIndexes,
                enabled: _inputEnabled,
                onCellTap: _selectCell,
              );
              final availableWidth = math.min(
                560.0,
                math.max(180.0, constraints.maxWidth - 24),
              );
              final statusHeight = constraints.maxHeight < 470 ? 42.0 : 48.0;
              final availableHeight = math.max(
                180.0,
                constraints.maxHeight - statusHeight - 20,
              );
              final boardDimension = math.min(availableWidth, availableHeight);
              final boardArea = SizedBox.square(
                key: ValueKey<String>(
                  widget.puzzle.size == 16
                      ? 'classic16-board-viewport'
                      : 'classic9-board-viewport',
                ),
                dimension: boardDimension,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: widget.puzzle.size == 16
                      ? InteractiveViewer(
                          transformationController: _boardTransform,
                          minScale: 1,
                          maxScale: 3.5,
                          boundaryMargin: const EdgeInsets.all(120),
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox.square(
                            dimension: boardDimension,
                            child: boardWidget,
                          ),
                        )
                      : boardWidget,
                ),
              );

              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Column(
                  children: [
                    if (!_ready)
                      const SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(),
                      ),
                    SizedBox(
                      height: statusHeight,
                      child: Row(
                        children: [
                          Expanded(
                            child: _GameStatusPill(
                              icon: Icons.error_outline_rounded,
                              text: mistakeLabel,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _GameStatusPill(
                              icon: Icons.lightbulb_outline_rounded,
                              text: context.tr('hints_count', <Object>[
                                widget.store.hints,
                              ]),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _GameStatusPill(
                              icon: widget.puzzle.size == 16
                                  ? Icons.zoom_out_map_rounded
                                  : Icons.grid_4x4_rounded,
                              text: widget.puzzle.size == 16
                                  ? '16×16 · 1–16'
                                  : context.strings.difficultyLabel(
                                      widget.puzzle.difficulty,
                                    ),
                              onTap: widget.puzzle.size == 16 ? _fitBoard : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedOpacity(
                              opacity: _paused ? 0 : 1,
                              duration: const Duration(milliseconds: 180),
                              child: IgnorePointer(
                                ignoring: _paused,
                                child: boardArea,
                              ),
                            ),
                            if (_paused)
                              SizedBox.square(
                                dimension: boardDimension,
                                child: UxStatePanel(
                                  icon: Icons.pause_circle_filled_rounded,
                                  title: UxCopy.pausedTitle(context),
                                  message: UxCopy.pausedBody(context),
                                  actionLabel: context.tr('continue_action'),
                                  onAction: _showPauseMenu,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GameStatusPill extends StatelessWidget {
  const _GameStatusPill({
    required this.icon,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 5),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: content,
      ),
    );
  }
}

class _GameResultSheet extends StatefulWidget {
  const _GameResultSheet({
    required this.title,
    required this.stars,
    required this.seconds,
    required this.mistakes,
    required this.hints,
    required this.showNextAction,
  });

  final String title;
  final int stars;
  final int seconds;
  final int mistakes;
  final int hints;
  final bool showNextAction;

  @override
  State<_GameResultSheet> createState() => _GameResultSheetState();
}

class _GameResultSheetState extends State<_GameResultSheet> {
  bool _rewardBusy = false;
  bool _rewardClaimed = false;
  String? _message;

  Future<void> _claimReward() async {
    if (_rewardBusy || _rewardClaimed) return;
    setState(() {
      _rewardBusy = true;
      _message = null;
    });
    final claimed =
        await EconomyService.instance.claimCareerRewardedInterstitial();
    if (!mounted) return;
    setState(() {
      _rewardBusy = false;
      _rewardClaimed = claimed;
      _message = claimed
          ? context.tr('coin_added_wallet', const <Object>[25])
          : context.tr('rewarded_ad_unavailable');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 62,
              color: Color(0xFFFFC94D),
            ),
            const SizedBox(height: 10),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                3,
                (index) => Icon(
                  index < widget.stars
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 44,
                  color: const Color(0xFFFFC94D),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                UxMetricTile(
                  label: context.tr('time'),
                  value: formatDuration(widget.seconds),
                  icon: Icons.timer_outlined,
                ),
                UxMetricTile(
                  label: context.tr('mistakes'),
                  value: '${widget.mistakes}',
                  icon: Icons.error_outline_rounded,
                ),
                UxMetricTile(
                  label: context.tr('hints'),
                  value: '${widget.hints}',
                  icon: Icons.lightbulb_outline_rounded,
                ),
              ],
            ),
            if (!AdsService.instance.noAds && !_rewardClaimed) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _rewardBusy ? null : _claimReward,
                icon: _rewardBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ondemand_video_outlined),
                label: Text(
                  context.tr('watch_and_earn_coin', const <Object>[25]),
                ),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                widget.showNextAction
                    ? _ResultAction.next
                    : _ResultAction.menu,
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                widget.showNextAction
                    ? context.tr('continue_action')
                    : context.tr('main_menu'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(_ResultAction.restart),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(context.tr('restart_puzzle')),
            ),
            if (widget.showNextAction)
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ResultAction.menu),
                child: Text(context.tr('main_menu')),
              ),
          ],
        ),
      ),
    );
  }
}
