import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../data/game_session_store.dart';
import '../../data/local_progress_store.dart';
import '../../data/samurai_game_session_store.dart';
import '../../data/ux_game_session_store.dart';
import '../../domain/samurai_sudoku.dart';
import '../../localization/app_strings.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/samurai_board.dart';
import '../../widgets/ux_feedback.dart';
import 'hint_economy.dart';

typedef SamuraiGameCompleted =
    Future<void> Function({
      required int seconds,
      required int mistakes,
      required int hints,
    });

enum SamuraiGameExit { menu }

enum _SamuraiPauseAction { resume, restart, menu }

enum _SamuraiLossAction { restart, menu }

enum _SamuraiResultAction { restart, menu }

class SamuraiGameScreen extends StatefulWidget {
  const SamuraiGameScreen({
    super.key,
    required this.puzzle,
    required this.store,
    this.onCompleted,
    this.initialSession,
    this.mistakeLimit = 3,
  });

  final SamuraiPuzzle puzzle;
  final LocalProgressStore store;
  final SamuraiGameCompleted? onCompleted;
  final SamuraiGameSession? initialSession;
  final int? mistakeLimit;

  @override
  State<SamuraiGameScreen> createState() => _SamuraiGameScreenState();
}

class _SamuraiGameScreenState extends State<SamuraiGameScreen>
    with WidgetsBindingObserver {
  final Stopwatch _stopwatch = Stopwatch();
  final ValueNotifier<int> _elapsedNotifier = ValueNotifier<int>(0);
  final Map<int, Set<int>> _notes = <int, Set<int>>{};
  final List<_SamuraiMove> _history = <_SamuraiMove>[];
  final Set<int> _hintedIndexes = <int>{};
  final SamuraiGameSessionStore _sessionStore =
      SamuraiGameSessionStore.instance;

  late List<int> _board;
  Timer? _clockTimer;
  Timer? _saveTimer;
  int? _selectedIndex;
  int? _errorIndex;
  int _elapsedSeconds = 0;
  int _elapsedOffsetSeconds = 0;
  int _mistakes = 0;
  int _hintsUsed = 0;
  bool _notesMode = false;
  bool _completed = false;
  bool _lost = false;
  bool _paused = false;
  bool _dialogVisible = false;
  bool _hintBusy = false;
  bool _allowExit = false;

  bool get _inputEnabled => !_completed && !_lost && !_paused;

  bool get _canUndo => _inputEnabled && _history.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(UxGameSessionStore.instance.clear());
    unawaited(GameSessionStore.instance.clearAll());
    final restored = widget.initialSession;
    if (restored != null && restored.puzzle.id == widget.puzzle.id) {
      _board = List<int>.from(restored.board);
      _notes.addAll(<int, Set<int>>{
        for (final entry in restored.notes.entries)
          entry.key: Set<int>.from(entry.value),
      });
      _hintedIndexes.addAll(restored.hintedIndexes);
      _elapsedSeconds = restored.elapsedSeconds;
      _elapsedOffsetSeconds = restored.elapsedSeconds;
      _elapsedNotifier.value = _elapsedSeconds;
      _mistakes = restored.mistakes;
      _hintsUsed = restored.hintsUsed;
      _notesMode = restored.notesMode;
    } else {
      _board = List<int>.from(widget.puzzle.puzzle);
    }
    _startClock();
    _schedulePersist();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_paused && !_lost && !_completed) _startClock();
    } else {
      _pauseClock();
      unawaited(_persistNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseClock();
    _saveTimer?.cancel();
    unawaited(_persistNow());
    _elapsedNotifier.dispose();
    super.dispose();
  }

  void _startClock() {
    if (_stopwatch.isRunning || _completed || _lost || _paused) return;
    _stopwatch.start();
    _clockTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_stopwatch.isRunning) return;
      final seconds = _elapsedOffsetSeconds + _stopwatch.elapsed.inSeconds;
      if (seconds != _elapsedSeconds) {
        _elapsedSeconds = seconds;
        _elapsedNotifier.value = seconds;
      }
    });
  }

  void _pauseClock() {
    _stopwatch.stop();
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  void _schedulePersist() {
    if (_completed || _lost) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_persistNow()),
    );
  }

  Future<void> _persistNow() async {
    if (_completed || _lost) return;
    await _sessionStore.save(
      SamuraiGameSession(
        puzzle: widget.puzzle,
        board: List<int>.from(_board),
        notes: <int, Set<int>>{
          for (final entry in _notes.entries)
            entry.key: Set<int>.from(entry.value),
        },
        hintedIndexes: Set<int>.from(_hintedIndexes),
        elapsedSeconds: _elapsedSeconds,
        mistakes: _mistakes,
        hintsUsed: _hintsUsed,
        notesMode: _notesMode,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _selectCell(int index) {
    if (!_inputEnabled || !SamuraiTopology.isActiveIndex(index)) return;
    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
  }

  void _enterNumber(int value) {
    final index = _selectedIndex;
    if (index == null ||
        !_inputEnabled ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index)) {
      return;
    }

    if (_notesMode && _board[index] == 0) {
      setState(() {
        final values = _notes.putIfAbsent(index, () => <int>{});
        values.contains(value) ? values.remove(value) : values.add(value);
        if (values.isEmpty) _notes.remove(index);
      });
      _schedulePersist();
      return;
    }

    if (widget.puzzle.solution[index] != value) {
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _mistakes++;
        _errorIndex = index;
      });
      _schedulePersist();
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
        _SamuraiMove(
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
    _schedulePersist();
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
        _SamuraiMove(
          index: index,
          previousValue: _board[index],
          previousNotes: Set<int>.from(_notes[index] ?? const <int>{}),
        ),
      );
      _board[index] = 0;
      _notes.remove(index);
      _errorIndex = null;
    });
    _schedulePersist();
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
    _schedulePersist();
  }

  void _toggleNotes() {
    if (!_inputEnabled) return;
    setState(() => _notesMode = !_notesMode);
    _schedulePersist();
  }

  Future<void> _hint() async {
    if (!_inputEnabled || _hintBusy) return;
    var index = _selectedIndex ?? -1;
    if (index < 0 ||
        !SamuraiTopology.isActiveIndex(index) ||
        widget.puzzle.isFixed(index) ||
        _hintedIndexes.contains(index) ||
        _board[index] != 0) {
      index = _firstEmptyIndex();
    }
    if (index < 0) return;

    setState(() => _hintBusy = true);
    try {
      final allowed = await HintEconomy.consumeOrAcquire(context, widget.store);
      if (!mounted || !allowed) return;
      if (_board[index] != 0) index = _firstEmptyIndex();
      if (index < 0) return;
      setState(() {
        _selectedIndex = index;
        _board[index] = widget.puzzle.solution[index];
        _hintedIndexes.add(index);
        _notes.remove(index);
        _removeRelatedNotes(index, _board[index]);
        _hintsUsed++;
      });
      _schedulePersist();
      await _checkCompletion();
    } finally {
      if (mounted) setState(() => _hintBusy = false);
    }
  }

  int _firstEmptyIndex() {
    for (final index in SamuraiTopology.activeIndexes) {
      if (_board[index] == 0) return index;
    }
    return -1;
  }

  void _removeRelatedNotes(int index, int value) {
    final peerIndexes = <int>{};
    for (final unitIndex in SamuraiTopology.unitsByCell[index]) {
      peerIndexes.addAll(SamuraiTopology.units[unitIndex]);
    }
    final emptyEntries = <int>[];
    for (final entry in _notes.entries) {
      if (!peerIndexes.contains(entry.key)) continue;
      entry.value.remove(value);
      if (entry.value.isEmpty) emptyEntries.add(entry.key);
    }
    for (final noteIndex in emptyEntries) {
      _notes.remove(noteIndex);
    }
  }

  Set<int> _completedValues() {
    return <int>{
      for (var value = 1; value <= 9; value++)
        if (_board.where((cell) => cell == value).length >=
            widget.puzzle.solution.where((cell) => cell == value).length)
          value,
    };
  }

  Future<void> _showPauseMenu() async {
    if (!mounted || _completed || _lost || _dialogVisible) return;
    _pauseClock();
    setState(() {
      _paused = true;
      _dialogVisible = true;
    });
    await _persistNow();
    if (!mounted) return;

    final action = await showAdaptiveBottomSheet<_SamuraiPauseAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => UxOutcomeSheet(
        icon: Icons.pause_circle_filled_rounded,
        title: sheetContext.tr('paused'),
        subtitle: sheetContext.tr('samurai_pause_body'),
        metrics: <Widget>[
          UxMetricTile(
            label: sheetContext.tr('time'),
            value: formatDuration(_elapsedSeconds),
            icon: Icons.timer_outlined,
          ),
          UxMetricTile(
            label: sheetContext.tr('mistakes'),
            value: widget.mistakeLimit == null
                ? '$_mistakes'
                : '$_mistakes/${widget.mistakeLimit}',
            icon: Icons.error_outline_rounded,
          ),
        ],
        primaryLabel: sheetContext.tr('continue_action'),
        onPrimary: () =>
            Navigator.of(sheetContext).pop(_SamuraiPauseAction.resume),
        secondaryLabel: sheetContext.tr('restart_puzzle'),
        onSecondary: () =>
            Navigator.of(sheetContext).pop(_SamuraiPauseAction.restart),
        tertiaryLabel: sheetContext.tr('main_menu'),
        onTertiary: () =>
            Navigator.of(sheetContext).pop(_SamuraiPauseAction.menu),
      ),
    );

    if (!mounted) return;
    setState(() => _dialogVisible = false);
    switch (action) {
      case _SamuraiPauseAction.resume:
        setState(() => _paused = false);
        _startClock();
        return;
      case _SamuraiPauseAction.restart:
        _restartPuzzle();
        return;
      case _SamuraiPauseAction.menu:
      case null:
        _exitToMenu();
        return;
    }
  }

  Future<void> _showLossSheet() async {
    if (!mounted || _dialogVisible || _completed) return;
    _pauseClock();
    setState(() {
      _lost = true;
      _dialogVisible = true;
    });
    await _sessionStore.clear();
    if (!mounted) return;

    final action = await showAdaptiveBottomSheet<_SamuraiLossAction>(
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
            value: '$_mistakes',
            icon: Icons.error_outline_rounded,
          ),
        ],
        primaryLabel: sheetContext.tr('restart_puzzle'),
        onPrimary: () =>
            Navigator.of(sheetContext).pop(_SamuraiLossAction.restart),
        tertiaryLabel: sheetContext.tr('main_menu'),
        onTertiary: () =>
            Navigator.of(sheetContext).pop(_SamuraiLossAction.menu),
      ),
    );

    if (!mounted) return;
    setState(() => _dialogVisible = false);
    if (action == _SamuraiLossAction.restart) {
      _restartPuzzle();
    } else {
      _exitToMenu();
    }
  }

  Future<void> _checkCompletion() async {
    if (_completed || !SamuraiEngine.isComplete(widget.puzzle, _board)) return;
    _pauseClock();
    setState(() => _completed = true);
    await _sessionStore.clear();
    await widget.onCompleted?.call(
      seconds: _elapsedSeconds,
      mistakes: _mistakes,
      hints: _hintsUsed,
    );
    if (!mounted) return;

    final action = await showAdaptiveBottomSheet<_SamuraiResultAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => UxOutcomeSheet(
        icon: Icons.emoji_events_rounded,
        title: sheetContext.tr('samurai_completed_title'),
        subtitle: sheetContext.tr('samurai_completed_body'),
        metrics: <Widget>[
          UxMetricTile(
            label: sheetContext.tr('time'),
            value: formatDuration(_elapsedSeconds),
            icon: Icons.timer_outlined,
          ),
          UxMetricTile(
            label: sheetContext.tr('mistakes'),
            value: '$_mistakes',
            icon: Icons.error_outline_rounded,
          ),
          UxMetricTile(
            label: sheetContext.tr('hints'),
            value: '$_hintsUsed',
            icon: Icons.lightbulb_outline_rounded,
          ),
        ],
        primaryLabel: sheetContext.tr('restart_puzzle'),
        onPrimary: () =>
            Navigator.of(sheetContext).pop(_SamuraiResultAction.restart),
        tertiaryLabel: sheetContext.tr('main_menu'),
        onTertiary: () =>
            Navigator.of(sheetContext).pop(_SamuraiResultAction.menu),
      ),
    );

    if (!mounted) return;
    if (action == _SamuraiResultAction.restart) {
      _restartPuzzle();
    } else {
      _exitToMenu();
    }
  }

  void _restartPuzzle() {
    _pauseClock();
    _stopwatch.reset();
    _elapsedOffsetSeconds = 0;
    setState(() {
      _board = List<int>.from(widget.puzzle.puzzle);
      _notes.clear();
      _history.clear();
      _hintedIndexes.clear();
      _selectedIndex = null;
      _errorIndex = null;
      _elapsedSeconds = 0;
      _elapsedNotifier.value = 0;
      _mistakes = 0;
      _hintsUsed = 0;
      _notesMode = false;
      _completed = false;
      _lost = false;
      _paused = false;
    });
    _startClock();
    _schedulePersist();
  }

  void _exitToMenu() {
    if (!mounted) return;
    _pauseClock();
    unawaited(_persistNow());
    setState(() => _allowExit = true);
    Navigator.of(context).pop(SamuraiGameExit.menu);
  }

  @override
  Widget build(BuildContext context) {
    final mistakeText = widget.mistakeLimit == null
        ? '$_mistakes'
        : '$_mistakes/${widget.mistakeLimit}';
    return PopScope<SamuraiGameExit>(
      canPop: _allowExit || _completed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_showPauseMenu());
      },
      child: Scaffold(
        bottomNavigationBar: NumberPadDock(
          child: NumberPad(
            maxValue: 9,
            completedValues: _completedValues(),
            enabled: _inputEnabled,
            notesEnabled: _notesMode,
            hintCount: widget.store.hints,
            onNumber: _enterNumber,
            onErase: _erase,
            onToggleNotes: _toggleNotes,
            onUndo: _canUndo ? _undo : null,
            onHint: _hint,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: InPageHeader(
                  title: context.tr('samurai_sudoku'),
                  padding: EdgeInsets.zero,
                  actions: <Widget>[
                    ValueListenableBuilder<int>(
                      valueListenable: _elapsedNotifier,
                      builder: (context, seconds, _) => Text(
                        formatDuration(seconds),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey<String>('samurai-action-pause'),
                      tooltip: context.tr('pause'),
                      onPressed: _inputEnabled ? _showPauseMenu : null,
                      icon: const Icon(Icons.pause_circle_outline_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.tr('samurai_zoom_hint'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      avatar: const Icon(Icons.error_outline_rounded, size: 17),
                      label: Text(mistakeText),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SamuraiBoard(
                    puzzle: widget.puzzle,
                    board: _board,
                    selectedIndex: _selectedIndex,
                    notes: _notes,
                    errorIndex: _errorIndex,
                    hintedIndexes: _hintedIndexes,
                    enabled: _inputEnabled,
                    onCellTap: _selectCell,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SamuraiMove {
  const _SamuraiMove({
    required this.index,
    required this.previousValue,
    required this.previousNotes,
  });

  final int index;
  final int previousValue;
  final Set<int> previousNotes;
}
