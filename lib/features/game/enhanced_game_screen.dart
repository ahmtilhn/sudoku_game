import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/responsive_layout.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../data/local_progress_store.dart';
import '../../data/ux_game_session_store.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
import '../../widgets/number_pad.dart';
import '../../widgets/sudoku_board.dart';
import 'hint_economy.dart';

typedef EnhancedGameCompleted = Future<void> Function({
  required int seconds,
  required int mistakes,
  required int hints,
});

enum EnhancedGameExit { next, menu }

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

  bool get _canUndo =>
      _ready && !_completed && !_roundLost && _history.isNotEmpty;

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
      _startClock();
    } else {
      _pauseClock();
      unawaited(_saveNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseClock();
    _saveDebounce?.cancel();
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
    if (!_ready || _completed || _roundLost || _stopwatch.isRunning) return;
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

  void _selectCell(int index) {
    if (!_ready || _completed || _roundLost) return;
    setState(() {
      _selectedIndex = index;
      _errorIndex = null;
    });
    _scheduleSave();
  }

  void _enterNumber(int value) {
    final index = _selectedIndex;
    if (index == null ||
        !_ready ||
        _completed ||
        _roundLost ||
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
        !_ready ||
        _completed ||
        _roundLost ||
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
    if (!_ready || _completed || _roundLost) return;
    setState(() => _notesMode = !_notesMode);
    _scheduleSave();
  }

  Future<void> _hint() async {
    if (!widget.allowHints ||
        !_ready ||
        _completed ||
        _roundLost ||
        _hintBusy) {
      return;
    }
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
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.flag_outlined, size: 48),
            const SizedBox(height: 10),
            Text(
              context.tr('round_lost'),
              textAlign: TextAlign.center,
              style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('mistake_limit_reached', <Object>[
                widget.mistakeLimit ?? 3,
              ]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: EconomyService.instance.balance >= _continueCost
                  ? () => Navigator.of(sheetContext).pop(_LossAction.coin)
                  : null,
              icon: const Icon(Icons.monetization_on_outlined),
              label: Text(
                context.tr('continue_with_coins', const <Object>[_continueCost]),
              ),
            ),
            if (!AdsService.instance.noAds) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(_LossAction.rewarded),
                icon: const Icon(Icons.ondemand_video_outlined),
                label: Text(context.tr('watch_rewarded_ad')),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(_LossAction.restart),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(context.tr('restart_puzzle')),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(_LossAction.exit),
              icon: const Icon(Icons.save_outlined),
              label: Text(context.tr('main_menu')),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _lossVisible = false);

    switch (action) {
      case _LossAction.coin:
        final continued = await EconomyService.instance.spendCareerContinue();
        if (!mounted) return;
        if (continued) {
          _resumeAfterLoss();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('not_enough_coins'))),
          );
          await _showLossSheet();
        }
      case _LossAction.rewarded:
        final continued = await AdsService.instance.showRewarded();
        if (!mounted) return;
        if (continued) {
          _resumeAfterLoss();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('rewarded_ad_unavailable'))),
          );
          await _showLossSheet();
        }
      case _LossAction.restart:
        _restartPuzzle();
      case _LossAction.exit:
      case null:
        await _saveNow();
        if (mounted) Navigator.of(context).pop(EnhancedGameExit.menu);
    }
  }

  void _resumeAfterLoss() {
    setState(() {
      _mistakes = 0;
      _roundLost = false;
      _errorIndex = null;
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
      _completed = false;
      _roundLost = false;
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
    for (final index in empty) {
      _notes.remove(index);
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
      builder: (sheetContext) => _GameResultSheet(
        title: widget.completionTitle ?? context.tr('congratulations'),
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
    final enabled = _ready && !_completed && !_roundLost;
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
          Semantics(
            label: context.tr('time'),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  formatDuration(_elapsedSeconds),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
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
          enabled: enabled,
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
                      if (!_ready) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.error_outline, size: 18),
                            label: Text(mistakeLabel),
                          ),
                          Chip(
                            avatar: const Icon(
                              Icons.lightbulb_outline,
                              size: 18,
                            ),
                            label: Text(
                              context.tr('hints_count', <Object>[
                                widget.store.hints,
                              ]),
                            ),
                          ),
                          Chip(
                            avatar: const Icon(Icons.grid_4x4, size: 18),
                            label: Text(
                              context.strings.difficultyLabel(
                                widget.puzzle.difficulty,
                              ),
                            ),
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
                        enabled: enabled,
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

enum _LossAction { coin, rewarded, restart, exit }
enum _ResultAction { next, restart, menu }

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
    final claimed = await EconomyService.instance
        .claimCareerRewardedInterstitial();
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(
              3,
              (index) => Icon(
                index < widget.stars
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                size: 46,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _ResultRow(
                    label: context.tr('time'),
                    value: formatDuration(widget.seconds),
                  ),
                  _ResultRow(
                    label: context.tr('mistakes'),
                    value: '${widget.mistakes}',
                  ),
                  _ResultRow(
                    label: context.tr('hints'),
                    value: '${widget.hints}',
                  ),
                ],
              ),
            ),
          ),
          if (!AdsService.instance.noAds && !_rewardClaimed) ...[
            const SizedBox(height: 12),
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
              widget.showNextAction ? _ResultAction.next : _ResultAction.menu,
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
            onPressed: () => Navigator.of(context).pop(_ResultAction.restart),
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(context.tr('restart_puzzle')),
          ),
          if (widget.showNextAction)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_ResultAction.menu),
              child: Text(context.tr('main_menu')),
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
