import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/career_catalog.dart';
import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../domain/classic16_puzzle_factory.dart';
import '../../domain/sudoku.dart';
import '../../domain/sudoku_variant.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../game/enhanced_game_screen.dart';

enum _CareerMode { journey, practice }

class CareerHubScreen extends StatefulWidget {
  const CareerHubScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<CareerHubScreen> createState() => _CareerHubScreenState();
}

class _CareerHubScreenState extends State<CareerHubScreen> {
  static const int _pageSize = 8;

  final EconomyService _economy = EconomyService.instance;
  SudokuVariant _variant = SudokuVariant.classic9;
  _CareerMode _mode = _CareerMode.journey;
  int _page = 0;
  int? _busyLevel;
  SudokuDifficulty? _busyPractice;
  bool _busyDaily = false;

  bool get _busy =>
      _busyLevel != null || _busyPractice != null || _busyDaily;

  @override
  void initState() {
    super.initState();
    _syncPageToProgress();
    _economy.addListener(_refresh);
    unawaited(_economy.initialize());
  }

  @override
  void dispose() {
    _economy.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _syncPageToProgress() {
    final next = widget.store.nextCareerLevelNumberFor(_variant);
    _page = (next - 1) ~/ _pageSize;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              final wide = constraints.maxWidth >= 780;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      compact ? 6 : 10,
                      14,
                      compact ? 8 : 14,
                    ),
                    child: Column(
                      children: [
                        _header(compact),
                        SizedBox(height: compact ? 6 : 8),
                        _variantSelector(compact),
                        SizedBox(height: compact ? 6 : 8),
                        SegmentedButton<_CareerMode>(
                          segments: [
                            ButtonSegment<_CareerMode>(
                              value: _CareerMode.journey,
                              icon: const Icon(Icons.route_rounded, size: 18),
                              label: Text(context.tr('career')),
                            ),
                            ButtonSegment<_CareerMode>(
                              value: _CareerMode.practice,
                              icon: const Icon(
                                Icons.sports_esports_rounded,
                                size: 18,
                              ),
                              label: Text(context.tr('practice')),
                            ),
                          ],
                          selected: <_CareerMode>{_mode},
                          onSelectionChanged: _busy
                              ? null
                              : (value) => setState(() => _mode = value.first),
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            minimumSize: WidgetStatePropertyAll<Size>(
                              Size(0, compact ? 38 : 42),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        SizedBox(height: compact ? 6 : 8),
                        Expanded(
                          child: _mode == _CareerMode.journey
                              ? _journey(compact: compact, wide: wide)
                              : _practice(compact: compact, wide: wide),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(bool compact) {
    return SizedBox(
      height: compact ? 42 : 46,
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('career'),
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 20 : 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _resource(
            const Icon(
              Icons.lightbulb_rounded,
              color: Color(0xFF35D2FF),
              size: 16,
            ),
            '${widget.store.hints}',
          ),
          const SizedBox(width: 5),
          _resource(
            const DuelAssetIcon(DuelAsset.coin, size: 25),
            '${_economy.balance}',
          ),
        ],
      ),
    );
  }

  Widget _resource(Widget icon, String value) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .13)),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _variantSelector(bool compact) {
    return SizedBox(
      height: compact ? 58 : 64,
      child: Row(
        children: [
          for (final variant in SudokuVariant.values) ...[
            Expanded(child: _variantButton(variant, compact)),
            if (variant != SudokuVariant.values.last)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _variantButton(SudokuVariant variant, bool compact) {
    final selected = _variant.id == variant.id;
    final is16 = variant.id == SudokuVariantId.classic16;
    final accent = is16 ? const Color(0xFF35D2FF) : const Color(0xFFFFC73D);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy
            ? null
            : () {
                setState(() {
                  _variant = variant;
                  _syncPageToProgress();
                });
              },
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: .15)
                : const Color(0xFF0A1728).withValues(alpha: .9),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: .11),
              width: selected ? 1.7 : 1,
            ),
          ),
          child: Row(
            children: [
              DuelAssetIcon(
                is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                size: compact ? 38 : 44,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accent : Colors.white,
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      is16 ? '1–16' : '1–9',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .55),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, color: accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _journey({required bool compact, required bool wide}) {
    final next = widget.store.nextCareerLevelNumberFor(_variant);
    final pageStart = _page * _pageSize + 1;
    final levels = List<int>.generate(_pageSize, (index) => pageStart + index);
    return Column(
      children: [
        _nextLevelStrip(next),
        SizedBox(height: compact ? 6 : 8),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: _page <= 0 || _busy
                    ? null
                    : () => setState(() => _page--),
                style: IconButton.styleFrom(
                  fixedSize: const Size(38, 38),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${context.tr('career')} · ${_page + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _busy ? null : () => setState(() => _page++),
                style: IconButton.styleFrom(
                  fixedSize: const Size(38, 38),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = wide ? 4 : 2;
              final rows = (_pageSize / columns).ceil();
              final gap = compact ? 6.0 : 8.0;
              final extent =
                  (constraints.maxHeight - gap * (rows - 1)) / rows;
              return GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: levels.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  mainAxisExtent: extent,
                ),
                itemBuilder: (context, index) => _levelTile(
                  level: levels[index],
                  next: next,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _nextLevelStrip(int level) {
    final difficulty = _difficultyForLevel(level);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => _openCareer(level),
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF12352A).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: const Color(0xFF29D398).withValues(alpha: .55),
            ),
          ),
          child: Row(
            children: [
              _busyLevel == level
                  ? const SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Color(0xFF29D398),
                      size: 30,
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${context.tr('continue_action')}  ',
                        style: const TextStyle(
                          color: Color(0xFF29D398),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text:
                            '${_variant.label} · ${context.strings.difficultyLabel(difficulty)} · $level',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${widget.store.completedCareerLevelCountFor(_variant)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _levelTile({required int level, required int next}) {
    final unlocked = widget.store.isCareerLevelUnlocked(
      level,
      variant: _variant,
    );
    final progress = widget.store.progressForCareerLevel(
      level,
      variant: _variant,
    );
    final current = level == next;
    final accent = current
        ? const Color(0xFF29D398)
        : progress != null
        ? const Color(0xFFFFC73D)
        : const Color(0xFF35D2FF);
    final stars = progress == null
        ? ''
        : List<String>.filled(progress.stars, '★').join();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: unlocked && !_busy ? () => _openCareer(level) : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1728).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unlocked
                  ? accent.withValues(alpha: current ? .72 : .32)
                  : Colors.white.withValues(alpha: .08),
              width: current ? 1.7 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_busyLevel == level)
                  const SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    unlocked
                        ? progress != null
                              ? Icons.workspace_premium_rounded
                              : Icons.grid_4x4_rounded
                        : Icons.lock_rounded,
                    color: unlocked ? accent : Colors.white30,
                    size: 25,
                  ),
                const SizedBox(height: 2),
                Text(
                  '$level',
                  style: TextStyle(
                    color: unlocked ? Colors.white : Colors.white38,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  context.strings.difficultyLabel(_difficultyForLevel(level)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unlocked
                        ? Colors.white.withValues(alpha: .58)
                        : Colors.white30,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (stars.isNotEmpty)
                  Text(
                    stars,
                    style: const TextStyle(
                      color: Color(0xFFFFC73D),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _practice({required bool compact, required bool wide}) {
    final entries = <({
      String title,
      String subtitle,
      SudokuDifficulty difficulty,
      bool daily,
    })>[
      (
        title: context.tr('daily_sudoku'),
        subtitle: context.tr('daily_subtitle'),
        difficulty: SudokuDifficulty.medium,
        daily: true,
      ),
      for (final difficulty in SudokuDifficulty.values)
        (
          title: context.strings.difficultyLabel(difficulty),
          subtitle: _variant.id == SudokuVariantId.classic16
              ? '${_variant.label} · 1–16'
              : context.tr('random_clue_count', <Object>[
                  PuzzleCatalog.targetClueCount(difficulty),
                ]),
          difficulty: difficulty,
          daily: false,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = wide ? 3 : 2;
        final rows = (entries.length / columns).ceil();
        final gap = compact ? 6.0 : 8.0;
        final extent = (constraints.maxHeight - gap * (rows - 1)) / rows;
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: extent,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _practiceTile(
              title: entry.title,
              subtitle: entry.subtitle,
              difficulty: entry.difficulty,
              daily: entry.daily,
            );
          },
        );
      },
    );
  }

  Widget _practiceTile({
    required String title,
    required String subtitle,
    required SudokuDifficulty difficulty,
    required bool daily,
  }) {
    final accent = daily ? const Color(0xFF29D398) : _accent(difficulty);
    final busy = daily ? _busyDaily : _busyPractice == difficulty;
    final progress = widget.store.progressFor(
      _practiceProgressId(difficulty, daily: daily),
      variant: _variant,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy
            ? null
            : daily
            ? _openDaily
            : () => _openPractice(difficulty),
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1728).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: accent.withValues(alpha: .4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                else
                  DuelAssetIcon(
                    _variant.id == SudokuVariantId.classic16
                        ? DuelAsset.board16Pro
                        : daily
                        ? DuelAsset.statusSuccessPro
                        : DuelAsset.board9Pro,
                    size: progress == null ? 48 : 40,
                  ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent.withValues(alpha: .8),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.tr('best_time', <Object>[
                      formatDuration(progress.bestSeconds),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 7,
                    runSpacing: 2,
                    children: [
                      Text(
                        context.tr('hints_count', <Object>[progress.bestHints]),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .68),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        context.tr('mistakes_count', <Object>[
                          progress.bestMistakes,
                        ]),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .68),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _practiceProgressId(
    SudokuDifficulty difficulty, {
    required bool daily,
  }) => daily ? 'practice-daily' : 'practice-${difficulty.name}';

  SudokuDifficulty _difficultyForLevel(int level) {
    if (_variant.id == SudokuVariantId.classic9) {
      return CareerCatalog.levelAt(level).difficulty;
    }
    final cycle = ((level - 1) ~/ 4).clamp(0, 4).toInt();
    return SudokuDifficulty.values[cycle];
  }

  Future<SudokuPuzzle> _careerPuzzle(int level) async {
    final difficulty = _difficultyForLevel(level);
    if (_variant.id == SudokuVariantId.classic9) {
      return Future<SudokuPuzzle>(
        () => CareerCatalog.puzzleFor(CareerCatalog.levelAt(level)),
      );
    }
    return Classic16PuzzleFactory.generate(
      difficulty: difficulty,
      seed: 16000 + level,
      id: 'career-$level',
      title: '${_variant.label} ${difficulty.label} $level',
    );
  }

  Future<void> _openCareer(int initialLevel) async {
    var level = initialLevel;
    while (mounted) {
      if (!widget.store.isCareerLevelUnlocked(level, variant: _variant)) return;
      setState(() => _busyLevel = level);
      try {
        final puzzle = await _careerPuzzle(level);
        if (!mounted) return;
        setState(() => _busyLevel = null);
        final result = await Navigator.of(context).push<EnhancedGameExit>(
          MaterialPageRoute(
            builder: (_) => EnhancedGameScreen(
              puzzle: puzzle,
              store: widget.store,
              completionTitle:
                  '${_variant.label} · ${context.strings.difficultyLabel(puzzle.difficulty)} · $level',
              onCompleted:
                  ({required seconds, required mistakes, required hints}) async {
                    final wasCompleted = widget.store.isCompleted(
                      'career-$level',
                      variant: _variant,
                    );
                    await widget.store.recordResult(
                      puzzleId: 'career-$level',
                      seconds: seconds,
                      mistakes: mistakes,
                      hints: hints,
                      variant: _variant,
                    );
                    if (!wasCompleted && level % 5 == 0) {
                      await widget.store.addHints(1);
                    }
                    await _claimEligibleAchievements();
                  },
            ),
          ),
        );
        if (!mounted || result != EnhancedGameExit.next) return;
        level++;
        setState(() => _page = (level - 1) ~/ _pageSize);
      } catch (_) {
        if (mounted) {
          setState(() => _busyLevel = null);
          await GameModal.error(
            context,
            title: context.tr('career'),
            message: context.tr('try_again'),
            retryLabel: context.tr('retry'),
            cancelLabel: context.tr('cancel'),
          );
        }
        return;
      }
    }
  }

  Future<void> _openPractice(SudokuDifficulty difficulty) async {
    setState(() => _busyPractice = difficulty);
    try {
      final puzzle = _variant.id == SudokuVariantId.classic16
          ? Classic16PuzzleFactory.generate(difficulty: difficulty)
          : PuzzleCatalog.generatePuzzle(difficulty);
      if (!mounted) return;
      setState(() => _busyPractice = null);
      await _openPuzzle(
        puzzle,
        summaryId: _practiceProgressId(difficulty, daily: false),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busyPractice = null);
        await _showGenerationError(context.tr('practice'));
      }
    }
  }

  Future<void> _openDaily() async {
    setState(() => _busyDaily = true);
    try {
      final now = DateTime.now();
      final seed = DateTime(now.year, now.month, now.day)
          .difference(DateTime(2025))
          .inDays
          .abs();
      final puzzle = _variant.id == SudokuVariantId.classic16
          ? Classic16PuzzleFactory.generate(
              difficulty: SudokuDifficulty.medium,
              seed: seed,
              id: 'daily-classic16-$seed',
              title: '${_variant.label} ${context.tr('daily_sudoku')}',
            )
          : PuzzleCatalog.dailyPuzzle(now);
      if (!mounted) return;
      setState(() => _busyDaily = false);
      await _openPuzzle(
        puzzle,
        summaryId: _practiceProgressId(
          SudokuDifficulty.medium,
          daily: true,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busyDaily = false);
        await _showGenerationError(context.tr('daily_sudoku'));
      }
    }
  }

  Future<void> _openPuzzle(
    SudokuPuzzle puzzle, {
    String? summaryId,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EnhancedGameScreen(
          puzzle: puzzle,
          store: widget.store,
          showNextAction: false,
          onCompleted:
              ({required seconds, required mistakes, required hints}) async {
                await widget.store.recordResult(
                  puzzleId: puzzle.id,
                  seconds: seconds,
                  mistakes: mistakes,
                  hints: hints,
                  variant: _variant,
                );
                if (summaryId != null && summaryId != puzzle.id) {
                  await widget.store.recordResult(
                    puzzleId: summaryId,
                    seconds: seconds,
                    mistakes: mistakes,
                    hints: hints,
                    variant: _variant,
                  );
                }
              },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showGenerationError(String title) async {
    await GameModal.error(
      context,
      title: title,
      message: context.tr('try_again'),
      retryLabel: context.tr('retry'),
      cancelLabel: context.tr('cancel'),
    );
  }

  Future<void> _claimEligibleAchievements() async {
    const achievements = <String>[
      'first_win',
      'games_25',
      'wins_10',
      'wins_50',
      'rating_1200',
      'rating_1500',
      'wins_250',
    ];
    for (final achievement in achievements) {
      await _economy.claimAchievement(achievement);
    }
  }

  Color _accent(SudokuDifficulty difficulty) => switch (difficulty) {
    SudokuDifficulty.beginner => const Color(0xFF29D398),
    SudokuDifficulty.easy => const Color(0xFF35D2FF),
    SudokuDifficulty.medium => const Color(0xFFFFC73D),
    SudokuDifficulty.hard => const Color(0xFFFF8B3D),
    SudokuDifficulty.expert => const Color(0xFFFF525E),
  };
}
