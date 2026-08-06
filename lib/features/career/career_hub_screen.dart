import 'dart:async';

import 'package:flutter/material.dart';

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
              final compact = constraints.maxHeight < 720;
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
                        _CareerHeader(
                          hints: widget.store.hints,
                          coins: _economy.balance,
                          onBack: () => Navigator.of(context).pop(),
                        ),
                        SizedBox(height: compact ? 7 : 12),
                        _VariantSelector(
                          selected: _variant,
                          compact: compact,
                          onChanged: _busy
                              ? null
                              : (variant) {
                                  setState(() {
                                    _variant = variant;
                                    _syncPageToProgress();
                                  });
                                },
                        ),
                        SizedBox(height: compact ? 7 : 10),
                        SegmentedButton<_CareerMode>(
                          segments: [
                            ButtonSegment(
                              value: _CareerMode.journey,
                              icon: const Icon(Icons.route_rounded),
                              label: Text(context.tr('career')),
                            ),
                            ButtonSegment(
                              value: _CareerMode.practice,
                              icon: const Icon(Icons.sports_esports_rounded),
                              label: Text(context.tr('practice')),
                            ),
                          ],
                          selected: <_CareerMode>{_mode},
                          onSelectionChanged: _busy
                              ? null
                              : (value) => setState(() => _mode = value.first),
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            minimumSize: WidgetStatePropertyAll(
                              Size(0, compact ? 42 : 48),
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 7 : 10),
                        Expanded(
                          child: _mode == _CareerMode.journey
                              ? _buildJourney(compact: compact, wide: wide)
                              : _buildPractice(compact: compact, wide: wide),
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

  Widget _buildJourney({required bool compact, required bool wide}) {
    final next = widget.store.nextCareerLevelNumberFor(_variant);
    final pageStart = _page * _pageSize + 1;
    final levels = List<int>.generate(_pageSize, (index) => pageStart + index);
    return Column(
      children: [
        _NextLevelStrip(
          variant: _variant,
          level: next,
          difficulty: _difficultyForLevel(next),
          busy: _busyLevel == next,
          completed: widget.store.completedCareerLevelCountFor(_variant),
          onTap: _busy ? null : () => _openCareer(next),
        ),
        SizedBox(height: compact ? 7 : 10),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: _page <= 0 || _busy
                  ? null
                  : () => setState(() => _page--),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${context.tr('career')} · ${_page + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: _busy ? null : () => setState(() => _page++),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        SizedBox(height: compact ? 5 : 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = wide ? 4 : 2;
              final rows = (_pageSize / columns).ceil();
              final gap = compact ? 7.0 : 10.0;
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
                itemBuilder: (context, index) {
                  final level = levels[index];
                  final unlocked = widget.store.isCareerLevelUnlocked(
                    level,
                    variant: _variant,
                  );
                  return _LevelTile(
                    level: level,
                    difficulty: _difficultyForLevel(level),
                    progress: widget.store.progressForCareerLevel(
                      level,
                      variant: _variant,
                    ),
                    unlocked: unlocked,
                    current: level == next,
                    busy: _busyLevel == level,
                    onTap: unlocked && !_busy
                        ? () => _openCareer(level)
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPractice({required bool compact, required bool wide}) {
    final entries = <_PracticeEntry>[
      _PracticeEntry(
        title: context.tr('daily_sudoku'),
        subtitle: context.tr('daily_subtitle'),
        difficulty: SudokuDifficulty.medium,
        daily: true,
      ),
      for (final difficulty in SudokuDifficulty.values)
        _PracticeEntry(
          title: context.strings.difficultyLabel(difficulty),
          subtitle: _variant.id == SudokuVariantId.classic16
              ? '${_variant.label} · 1–16'
              : context.tr('random_clue_count', <Object>[
                  PuzzleCatalog.targetClueCount(difficulty),
                ]),
          difficulty: difficulty,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = wide ? 3 : 2;
        final rows = (entries.length / columns).ceil();
        final gap = compact ? 7.0 : 10.0;
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
            return _PracticeTile(
              entry: entry,
              variant: _variant,
              busy: entry.daily
                  ? _busyDaily
                  : _busyPractice == entry.difficulty,
              onTap: _busy
                  ? null
                  : entry.daily
                  ? _openDaily
                  : () => _openPractice(entry.difficulty),
            );
          },
        );
      },
    );
  }

  SudokuDifficulty _difficultyForLevel(int level) {
    if (_variant.id == SudokuVariantId.classic9) {
      return CareerCatalog.levelAt(level).difficulty;
    }
    final cycle = ((level - 1) ~/ 4).clamp(0, 4);
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
        setState(() {
          _page = (level - 1) ~/ _pageSize;
        });
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
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EnhancedGameScreen(
            puzzle: puzzle,
            store: widget.store,
            showNextAction: false,
            onCompleted:
                ({required seconds, required mistakes, required hints}) =>
                    widget.store.recordResult(
                      puzzleId: puzzle.id,
                      seconds: seconds,
                      mistakes: mistakes,
                      hints: hints,
                      variant: _variant,
                    ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busyPractice = null);
        await GameModal.error(
          context,
          title: context.tr('practice'),
          message: context.tr('try_again'),
          retryLabel: context.tr('retry'),
          cancelLabel: context.tr('cancel'),
        );
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
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EnhancedGameScreen(
            puzzle: puzzle,
            store: widget.store,
            showNextAction: false,
            onCompleted:
                ({required seconds, required mistakes, required hints}) =>
                    widget.store.recordResult(
                      puzzleId: puzzle.id,
                      seconds: seconds,
                      mistakes: mistakes,
                      hints: hints,
                      variant: _variant,
                    ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busyDaily = false);
        await GameModal.error(
          context,
          title: context.tr('daily_sudoku'),
          message: context.tr('try_again'),
          retryLabel: context.tr('retry'),
          cancelLabel: context.tr('cancel'),
        );
      }
    }
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
}

class _CareerHeader extends StatelessWidget {
  const _CareerHeader({
    required this.hints,
    required this.coins,
    required this.onBack,
  });

  final int hints;
  final int coins;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('career'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _ResourcePill(
            icon: const Icon(
              Icons.lightbulb_rounded,
              color: Color(0xFF35D2FF),
              size: 18,
            ),
            value: '$hints',
          ),
          const SizedBox(width: 6),
          _ResourcePill(
            icon: const DuelAssetIcon(DuelAsset.coin, size: 18),
            value: '$coins',
          ),
        ],
      ),
    );
  }
}

class _ResourcePill extends StatelessWidget {
  const _ResourcePill({required this.icon, required this.value});

  final Widget icon;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF0A1728).withValues(alpha: .92),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .13)),
    ),
    child: Row(
      children: [
        icon,
        const SizedBox(width: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _VariantSelector extends StatelessWidget {
  const _VariantSelector({
    required this.selected,
    required this.compact,
    required this.onChanged,
  });

  final SudokuVariant selected;
  final bool compact;
  final ValueChanged<SudokuVariant>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 78 : 94,
      child: Row(
        children: [
          for (final variant in SudokuVariant.values) ...[
            Expanded(
              child: _VariantButton(
                variant: variant,
                selected: selected.id == variant.id,
                compact: compact,
                onTap: onChanged == null ? null : () => onChanged!(variant),
              ),
            ),
            if (variant != SudokuVariant.values.last)
              const SizedBox(width: 9),
          ],
        ],
      ),
    );
  }
}

class _VariantButton extends StatelessWidget {
  const _VariantButton({
    required this.variant,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final SudokuVariant variant;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final is16 = variant.id == SudokuVariantId.classic16;
    final accent = is16 ? const Color(0xFF35D2FF) : const Color(0xFFFFC73D);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: .16)
                : const Color(0xFF0A1728).withValues(alpha: .9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: .12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              DuelAssetIcon(
                is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                size: compact ? 54 : 70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.label,
                      style: TextStyle(
                        color: selected ? accent : Colors.white,
                        fontSize: compact ? 16 : 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      is16 ? '1–16' : '1–9',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextLevelStrip extends StatelessWidget {
  const _NextLevelStrip({
    required this.variant,
    required this.level,
    required this.difficulty,
    required this.busy,
    required this.completed,
    required this.onTap,
  });

  final SudokuVariant variant;
  final int level;
  final SudokuDifficulty difficulty;
  final bool busy;
  final int completed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Ink(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12352A).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: const Color(0xFF29D398).withValues(alpha: .58),
          ),
        ),
        child: Row(
          children: [
            busy
                ? const SizedBox.square(
                    dimension: 30,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Color(0xFF29D398),
                    size: 38,
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('continue_action'),
                    style: const TextStyle(
                      color: Color(0xFF29D398),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${variant.label} · ${context.strings.difficultyLabel(difficulty)} · $level',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$completed',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.difficulty,
    required this.progress,
    required this.unlocked,
    required this.current,
    required this.busy,
    required this.onTap,
  });

  final int level;
  final SudokuDifficulty difficulty;
  final LevelProgress? progress;
  final bool unlocked;
  final bool current;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = current
        ? const Color(0xFF29D398)
        : progress != null
        ? const Color(0xFFFFC73D)
        : const Color(0xFF35D2FF);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1728).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: unlocked
                  ? accent.withValues(alpha: current ? .75 : .34)
                  : Colors.white.withValues(alpha: .08),
              width: current ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 30,
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
                    size: 30,
                  ),
                const SizedBox(height: 4),
                Text(
                  '$level',
                  style: TextStyle(
                    color: unlocked ? Colors.white : Colors.white38,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  context.strings.difficultyLabel(difficulty),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unlocked
                        ? Colors.white.withValues(alpha: .6)
                        : Colors.white30,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (progress != null)
                  Text(
                    '★' * progress!.stars,
                    style: const TextStyle(
                      color: Color(0xFFFFC73D),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PracticeEntry {
  const _PracticeEntry({
    required this.title,
    required this.subtitle,
    required this.difficulty,
    this.daily = false,
  });

  final String title;
  final String subtitle;
  final SudokuDifficulty difficulty;
  final bool daily;
}

class _PracticeTile extends StatelessWidget {
  const _PracticeTile({
    required this.entry,
    required this.variant,
    required this.busy,
    required this.onTap,
  });

  final _PracticeEntry entry;
  final SudokuVariant variant;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = entry.daily
        ? const Color(0xFF29D398)
        : _difficultyAccent(entry.difficulty);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1728).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: accent.withValues(alpha: .42)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 38,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                else
                  DuelAssetIcon(
                    variant.id == SudokuVariantId.classic16
                        ? DuelAsset.board16Pro
                        : entry.daily
                        ? DuelAsset.statusSuccessPro
                        : DuelAsset.board9Pro,
                    size: 58,
                  ),
                const SizedBox(height: 5),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  entry.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent.withValues(alpha: .8),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _difficultyAccent(SudokuDifficulty difficulty) => switch (difficulty) {
  SudokuDifficulty.beginner => const Color(0xFF29D398),
  SudokuDifficulty.easy => const Color(0xFF35D2FF),
  SudokuDifficulty.medium => const Color(0xFFFFC73D),
  SudokuDifficulty.hard => const Color(0xFFFF8B3D),
  SudokuDifficulty.expert => const Color(0xFFFF525E),
};
