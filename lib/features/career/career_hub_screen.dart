import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/career_catalog.dart';
import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../domain/classic16_puzzle_factory.dart';
import '../../domain/samurai_sudoku.dart';
import '../../domain/sudoku.dart';
import '../../domain/sudoku_variant.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../game/enhanced_game_screen.dart';
import '../game/samurai_game_screen.dart';

class CareerHubScreen extends StatefulWidget {
  const CareerHubScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<CareerHubScreen> createState() => _CareerHubScreenState();
}

class _CareerHubScreenState extends State<CareerHubScreen>
    with SingleTickerProviderStateMixin {
  static const int _chapterSize = 10;

  final EconomyService _economy = EconomyService.instance;
  late final TabController _tabs;
  SudokuVariant _careerVariant = SudokuVariant.classic9;
  late int _chapter;
  int? _generatingLevel;
  SudokuDifficulty? _generatingPractice;
  bool _generatingDaily = false;
  bool _generatingSamurai = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _chapter = _chapterForVariant(_careerVariant);
    _economy.addListener(_refresh);
    unawaited(_economy.initialize());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _economy.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _busy =>
      _generatingLevel != null ||
      _generatingPractice != null ||
      _generatingDaily ||
      _generatingSamurai;

  int _chapterForVariant(SudokuVariant variant) =>
      (widget.store.nextCareerLevelNumberFor(variant) - 1) ~/ _chapterSize + 1;

  void _selectCareerVariant(SudokuVariant variant) {
    if (_careerVariant == variant || _busy) return;
    setState(() {
      _careerVariant = variant;
      _chapter = _chapterForVariant(variant);
    });
  }

  @override
  Widget build(BuildContext context) {
    final compactHeader =
        MediaQuery.sizeOf(context).width < 390 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('career')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: compactHeader
                ? Chip(
                    avatar: const DuelAssetIcon(
                      DuelAsset.coin,
                      size: 18,
                      color: Color(0xFFFFC94D),
                    ),
                    label: Text('${widget.store.hints} · ${_economy.balance}'),
                  )
                : Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: const DuelAssetIcon(
                          DuelAsset.lightbulb,
                          size: 18,
                        ),
                        label: Text('${widget.store.hints}'),
                      ),
                      Chip(
                        avatar: const DuelAssetIcon(
                          DuelAsset.coin,
                          size: 18,
                          color: Color(0xFFFFC94D),
                        ),
                        label: Text('${_economy.balance}'),
                      ),
                    ],
                  ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: context.tr('career')),
            Tab(text: context.tr('practice')),
          ],
        ),
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
          child: TabBarView(
            controller: _tabs,
            children: [_careerTab(), _practiceTab()],
          ),
        ),
      ),
    );
  }

  Widget _careerTab() {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final variant = _careerVariant;
        final nextNumber = widget.store.nextCareerLevelNumberFor(variant);
        final nextLevel = CareerCatalog.levelAt(nextNumber);
        final chapterStart = (_chapter - 1) * _chapterSize + 1;
        final levels = List<CareerLevel>.generate(
          _chapterSize,
          (index) => CareerCatalog.levelAt(chapterStart + index),
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final cardExtent = largeText ? 248.0 : 196.0;
            final cardMaxExtent = largeText ? 340.0 : 246.0;
            final completed = widget.store.completedCareerLevelCountFor(
              variant,
            );
            final designedCompleted = completed
                .clamp(0, CareerCatalog.designedLevelCount)
                .toInt();
            final starsThrough = nextNumber > CareerCatalog.designedLevelCount
                ? nextNumber - 1
                : CareerCatalog.designedLevelCount;
            final totalStars = CareerCatalog.levelsThrough(starsThrough)
                .fold<int>(
                  0,
                  (total, level) =>
                      total +
                      (widget.store
                              .progressForCareerLevel(
                                level.number,
                                variant: variant,
                              )
                              ?.stars ??
                          0),
                );
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _HeroPanel(
                      title: context.tr('career'),
                      subtitle: context.tr('career_intro'),
                      icon: DuelAsset.homeCareerRelic,
                      trailing: context.tr('completed_levels', <Object>[
                        completed,
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _CareerVariantSelector(
                      selected: variant,
                      enabled: !_busy,
                      onSelected: _selectCareerVariant,
                    ),
                    const SizedBox(height: 12),
                    _CareerProgressPanel(
                      completed: designedCompleted,
                      total: CareerCatalog.designedLevelCount,
                      stars: totalStars,
                      totalCompleted: completed,
                      variant: variant,
                      nextLevel: nextLevel,
                    ),
                    const SizedBox(height: 14),
                    _NextLevelCard(
                      level: nextLevel,
                      progress: widget.store.progressForCareerLevel(
                        nextLevel.number,
                        variant: variant,
                      ),
                      variant: variant,
                      loading: _generatingLevel == nextLevel.number,
                      onTap: _busy ? null : () => _openCareer(nextLevel),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).previousPageTooltip,
                          onPressed: _chapter <= 1 || _busy
                              ? null
                              : () => setState(() => _chapter--),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${context.tr('career')} · $_chapter',
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _chapter = _chapterForVariant(variant);
                                      }),
                                child: Text(
                                  context.tr('level_title', <Object>[
                                    context.strings.difficultyLabel(
                                      nextLevel.difficulty,
                                    ),
                                    nextNumber,
                                  ]),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).nextPageTooltip,
                          onPressed: _busy
                              ? null
                              : () => setState(() => _chapter++),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: levels.length,
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: cardMaxExtent,
                        mainAxisExtent: cardExtent,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) {
                        final level = levels[index];
                        return _LevelCard(
                          level: level,
                          progress: widget.store.progressForCareerLevel(
                            level.number,
                            variant: variant,
                          ),
                          unlocked: widget.store.isCareerLevelUnlocked(
                            level.number,
                            variant: variant,
                          ),
                          current: level.number == nextNumber,
                          loading: _generatingLevel == level.number,
                          onTap:
                              widget.store.isCareerLevelUnlocked(
                                    level.number,
                                    variant: variant,
                                  ) &&
                                  !_busy
                              ? () => _openCareer(level)
                              : null,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _practiceTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth >= 840 ? 760.0 : 680.0;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _HeroPanel(
                  title: context.tr('practice'),
                  subtitle: context.tr('career_random_intro'),
                  icon: DuelAsset.grid,
                ),
                const SizedBox(height: 14),
                _PracticeCard(
                  icon: Icons.today_rounded,
                  title: context.tr('daily_sudoku'),
                  subtitle: _practiceSubtitle(
                    context,
                    progress: widget.store.progressFor(
                      PuzzleCatalog.dailyPuzzle(DateTime.now()).id,
                    ),
                    fallback: context.tr('daily_subtitle'),
                  ),
                  accent: const Color(0xFF29D398),
                  loading: _generatingDaily,
                  onTap: _busy ? null : _openDaily,
                ),
                const SizedBox(height: 10),
                _PracticeCard(
                  icon: Icons.dashboard_customize_rounded,
                  title: context.tr('samurai_sudoku'),
                  subtitle: context.tr('samurai_subtitle'),
                  accent: const Color(0xFFE8794F),
                  loading: _generatingSamurai,
                  onTap: _busy ? null : _openSamurai,
                ),
                const SizedBox(height: 10),
                for (final difficulty in SudokuDifficulty.values) ...[
                  _PracticeCard(
                    icon: Icons.grid_4x4_rounded,
                    title: context.strings.difficultyLabel(difficulty),
                    subtitle: _practiceSubtitle(
                      context,
                      progress: widget.store.progressFor(
                        'practice-${difficulty.name}',
                      ),
                      fallback: context.tr('random_clue_count', <Object>[
                        PuzzleCatalog.targetClueCount(difficulty),
                      ]),
                    ),
                    accent: _difficultyAccent(difficulty),
                    loading: _generatingPractice == difficulty,
                    onTap: _busy ? null : () => _openPractice(difficulty),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _practiceSubtitle(
    BuildContext context, {
    required LevelProgress? progress,
    required String fallback,
  }) {
    if (progress == null) return fallback;
    return [
      context.tr('best_time', <Object>[formatDuration(progress.bestSeconds)]),
      context.tr('mistakes_count', <Object>[progress.bestMistakes]),
      context.tr('hints_count', <Object>[progress.bestHints]),
    ].join(' - ');
  }

  Future<void> _openCareer(CareerLevel initialLevel) async {
    var level = initialLevel;
    final variant = _careerVariant;
    while (mounted) {
      if (!widget.store.isCareerLevelUnlocked(level.number, variant: variant)) {
        return;
      }
      setState(() => _generatingLevel = level.number);
      final puzzle = await Future<SudokuPuzzle>(
        () => _careerPuzzleFor(level, variant),
      );
      if (!mounted) return;
      setState(() => _generatingLevel = null);
      final wasCompleted = widget.store.isCompleted(level.id, variant: variant);
      final result = await Navigator.of(context).push<EnhancedGameExit>(
        MaterialPageRoute(
          builder: (gameContext) => EnhancedGameScreen(
            puzzle: puzzle,
            store: widget.store,
            completionTitle: gameContext.tr('level_title', <Object>[
              gameContext.strings.difficultyLabel(level.difficulty),
              level.number,
            ]),
            onCompleted:
                ({required seconds, required mistakes, required hints}) async {
                  await widget.store.recordResult(
                    puzzleId: level.id,
                    seconds: seconds,
                    mistakes: mistakes,
                    hints: hints,
                    variant: variant,
                  );
                  if (!wasCompleted && level.hintReward > 0) {
                    await widget.store.addHints(level.hintReward);
                  }
                  await _claimEligibleAchievements();
                },
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _chapter = _chapterForVariant(variant);
      });
      if (result != EnhancedGameExit.next) return;
      level = CareerCatalog.levelAt(level.number + 1);
    }
  }

  SudokuPuzzle _careerPuzzleFor(CareerLevel level, SudokuVariant variant) {
    if (variant.id == SudokuVariantId.classic16) {
      return Classic16PuzzleFactory.generate(
        difficulty: level.difficulty,
        seed: level.seed,
        id: level.id,
        title: '16x16 Level ${level.number}',
      );
    }
    return CareerCatalog.puzzleFor(level);
  }

  Future<void> _openPractice(SudokuDifficulty difficulty) async {
    setState(() => _generatingPractice = difficulty);
    final puzzle = await Future<SudokuPuzzle>(
      () => PuzzleCatalog.generatePuzzle(difficulty),
    );
    if (!mounted) return;
    setState(() => _generatingPractice = null);
    await _openStandalonePuzzle(
      puzzle,
      progressId: 'practice-${difficulty.name}',
    );
  }

  Future<void> _openSamurai() async {
    final difficulty = await showModalBottomSheet<SudokuDifficulty>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              sheetContext.tr('samurai_choose_difficulty'),
              textAlign: TextAlign.center,
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            for (final value in SudokuDifficulty.values)
              ListTile(
                leading: Icon(
                  Icons.dashboard_customize_rounded,
                  color: _difficultyAccent(value),
                ),
                title: Text(
                  sheetContext.strings.difficultyLabel(value),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
    if (!mounted || difficulty == null) return;

    setState(() => _generatingSamurai = true);
    final puzzle = await Future<SamuraiPuzzle>(
      () => SamuraiEngine.generate(difficulty: difficulty),
    );
    if (!mounted) return;
    setState(() => _generatingSamurai = false);

    await Navigator.of(context).push<SamuraiGameExit>(
      MaterialPageRoute(
        builder: (_) => SamuraiGameScreen(
          puzzle: puzzle,
          store: widget.store,
          onCompleted:
              ({required seconds, required mistakes, required hints}) async {
                await widget.store.recordResult(
                  puzzleId: 'practice-samurai-${difficulty.name}',
                  seconds: seconds,
                  mistakes: mistakes,
                  hints: hints,
                );
                await _claimEligibleAchievements();
              },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openDaily() async {
    setState(() => _generatingDaily = true);
    final puzzle = await Future<SudokuPuzzle>(
      () => PuzzleCatalog.dailyPuzzle(DateTime.now()),
    );
    if (!mounted) return;
    setState(() => _generatingDaily = false);
    await _openStandalonePuzzle(puzzle, progressId: puzzle.id);
  }

  Future<void> _openStandalonePuzzle(
    SudokuPuzzle puzzle, {
    required String progressId,
  }) async {
    await Navigator.of(context).push<EnhancedGameExit>(
      MaterialPageRoute(
        builder: (_) => EnhancedGameScreen(
          puzzle: puzzle,
          store: widget.store,
          showNextAction: false,
          onCompleted:
              ({required seconds, required mistakes, required hints}) async {
                await widget.store.recordResult(
                  puzzleId: progressId,
                  seconds: seconds,
                  mistakes: mistakes,
                  hints: hints,
                );
                await _claimEligibleAchievements();
              },
        ),
      ),
    );
    if (mounted) setState(() {});
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

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String icon;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF172B37).withValues(alpha: .96),
            const Color(0xFF101B20).withValues(alpha: .96),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 56 : 64,
              height: compact ? 56 : 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(18),
              ),
              child: DuelAssetIcon(icon, size: compact ? 44 : 52),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 20 : 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: compact ? 4 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC94D).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        trailing!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFC94D),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CareerVariantSelector extends StatelessWidget {
  const _CareerVariantSelector({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final SudokuVariant selected;
  final bool enabled;
  final ValueChanged<SudokuVariant> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101B20).withValues(alpha: .88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<SudokuVariant>(
          segments: [
            for (final variant in SudokuVariant.values)
              ButtonSegment<SudokuVariant>(
                value: variant,
                icon: Icon(
                  variant.id == SudokuVariantId.classic16
                      ? Icons.grid_on_rounded
                      : Icons.grid_4x4_rounded,
                ),
                label: Text(variant.label),
              ),
          ],
          selected: <SudokuVariant>{selected},
          onSelectionChanged: enabled
              ? (values) => onSelected(values.first)
              : null,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.black.withValues(alpha: .84)
                  : Colors.white,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFFFFC94D)
                  : Colors.white.withValues(alpha: .04),
            ),
            side: WidgetStateProperty.all(
              BorderSide(color: Colors.white.withValues(alpha: .10)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CareerProgressPanel extends StatelessWidget {
  const _CareerProgressPanel({
    required this.completed,
    required this.total,
    required this.stars,
    required this.totalCompleted,
    required this.variant,
    required this.nextLevel,
  });

  final int completed;
  final int total;
  final int stars;
  final int totalCompleted;
  final SudokuVariant variant;
  final CareerLevel nextLevel;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101B20).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DuelAssetIcon(
                  DuelAsset.homeCareerRelic,
                  size: 22,
                  color: Color(0xFF3AA9FF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    variant.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: Color(0xFFFFC94D),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF3AA9FF),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 420 ? 2 : 4;
                final width =
                    (constraints.maxWidth - ((columns - 1) * 8)) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: width,
                      child: _CareerMetric(
                        value: totalCompleted > total
                            ? '$completed/$total+'
                            : '$completed/$total',
                        label: 'Milestone',
                        asset: DuelAsset.grid,
                        color: const Color(0xFF3AA9FF),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _CareerMetric(
                        value: '$stars',
                        label: 'Stars',
                        asset: DuelAsset.trophy,
                        color: const Color(0xFFFFC94D),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _CareerMetric(
                        value: totalCompleted > total
                            ? 'Endless'
                            : '${nextLevel.chapter}',
                        label: totalCompleted > total ? 'Track' : 'Chapter',
                        asset: DuelAsset.careerBook,
                        color: const Color(0xFF29D398),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _CareerMetric(
                        value: '${nextLevel.number}',
                        label: 'Next level',
                        asset: DuelAsset.leaderboardCrownPro,
                        color: _difficultyAccent(nextLevel.difficulty),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CareerMetric extends StatelessWidget {
  const _CareerMetric({
    required this.value,
    required this.label,
    required this.asset,
    required this.color,
  });

  final String value;
  final String label;
  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DuelAssetIcon(asset, size: 18, color: color),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .58),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextLevelCard extends StatelessWidget {
  const _NextLevelCard({
    required this.level,
    required this.progress,
    required this.variant,
    required this.loading,
    required this.onTap,
  });

  final CareerLevel level;
  final LevelProgress? progress;
  final SudokuVariant variant;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _difficultyAccent(level.difficulty);
    final compact = MediaQuery.sizeOf(context).width < 390;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: .18),
                const Color(0xFF101B20).withValues(alpha: .94),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: .36)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: loading
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              color: accent,
                              strokeWidth: 2.4,
                            ),
                          )
                        : Icon(
                            Icons.play_arrow_rounded,
                            color: accent,
                            size: 42,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _DifficultyChip(
                              label: context.strings.difficultyLabel(
                                level.difficulty,
                              ),
                              color: accent,
                            ),
                            _DifficultyChip(
                              label: variant.label,
                              color: const Color(0xFF3AA9FF),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr('level_title', <Object>[
                            context.strings.difficultyLabel(level.difficulty),
                            level.number,
                          ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 19 : 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    _PlayButton(accent: accent, onTap: onTap),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.timer_outlined,
                    label: progress == null
                        ? context.tr('new_level')
                        : context.tr('best_time', <Object>[
                            formatDuration(progress!.bestSeconds),
                          ]),
                    color: Colors.white.withValues(alpha: .70),
                  ),
                  _RewardPill(level: level),
                  if (progress != null)
                    _StarRow(stars: progress!.stars, color: accent),
                ],
              ),
              if (compact) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _PlayButton(accent: accent, onTap: onTap),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.play_arrow_rounded, size: 19),
      label: Text(context.tr('continue_action')),
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.black.withValues(alpha: .84),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 96,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardPill extends StatelessWidget {
  const _RewardPill({required this.level});

  final CareerLevel level;

  @override
  Widget build(BuildContext context) {
    final hintText = level.hintReward > 0 ? ' · +${level.hintReward}' : '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFC94D).withValues(alpha: .11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DuelAssetIcon(
              DuelAsset.coin,
              size: 14,
              color: Color(0xFFFFC94D),
            ),
            const SizedBox(width: 5),
            Text(
              '+${level.coinReward}$hintText',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.stars, required this.color});

  final int stars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(
            3,
            (index) => Icon(
              index < stars ? Icons.star_rounded : Icons.star_border_rounded,
              size: 15,
              color: const Color(0xFFFFC94D),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.progress,
    required this.unlocked,
    required this.current,
    required this.loading,
    required this.onTap,
  });

  final CareerLevel level;
  final LevelProgress? progress;
  final bool unlocked;
  final bool current;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _difficultyAccent(level.difficulty);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final completed = progress != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unlocked
                ? const Color(0xFF101B20).withValues(alpha: .95)
                : const Color(0xFF0B1215).withValues(alpha: .78),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: current
                  ? accent
                  : completed
                  ? const Color(0xFF29D398).withValues(alpha: .24)
                  : accent.withValues(alpha: unlocked ? .24 : .10),
              width: current ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: accent.withValues(alpha: .16),
                    child: loading
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        : Icon(
                            !unlocked
                                ? Icons.lock_outline_rounded
                                : completed
                                ? Icons.check_rounded
                                : Icons.grid_4x4_rounded,
                            color: unlocked
                                ? accent
                                : Colors.white.withValues(alpha: .36),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _DifficultyChip(
                          label: context.strings.difficultyLabel(
                            level.difficulty,
                          ),
                          color: accent,
                        ),
                        if (current)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              context.tr('continue_action'),
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        if (progress != null)
                          _StarRow(stars: progress!.stars, color: accent),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'Level ${level.number}',
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unlocked
                      ? Colors.white
                      : Colors.white.withValues(alpha: .42),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                !unlocked
                    ? context.tr('complete_previous_level')
                    : progress == null
                    ? context.tr('new_level')
                    : context.tr('best_time', <Object>[
                        formatDuration(progress!.bestSeconds),
                      ]),
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unlocked
                      ? accent.withValues(alpha: .9)
                      : Colors.white.withValues(alpha: .34),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _RewardPill(level: level),
                  if (progress == null)
                    _InfoPill(
                      icon: unlocked
                          ? Icons.radio_button_checked_rounded
                          : Icons.lock_outline_rounded,
                      label: current
                          ? context.tr('continue_action')
                          : unlocked
                          ? context.tr('new_level')
                          : 'Locked',
                      color: unlocked
                          ? accent
                          : Colors.white.withValues(alpha: .46),
                    ),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress!.stars / 3,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: .08),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF101B20).withValues(alpha: .95),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: accent.withValues(alpha: .22)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Icon(icon, color: accent, size: 31),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .64),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

Color _difficultyAccent(SudokuDifficulty difficulty) {
  return switch (difficulty) {
    SudokuDifficulty.beginner => const Color(0xFF29D398),
    SudokuDifficulty.easy => const Color(0xFF3AA9FF),
    SudokuDifficulty.medium => const Color(0xFFFFC94D),
    SudokuDifficulty.hard => const Color(0xFFFF8A3D),
    SudokuDifficulty.expert => const Color(0xFFFF5C7A),
  };
}
