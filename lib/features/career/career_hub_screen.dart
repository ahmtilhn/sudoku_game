import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/career_catalog.dart';
import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../domain/samurai_sudoku.dart';
import '../../domain/sudoku.dart';
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
  late int _chapter;
  int? _generatingLevel;
  SudokuDifficulty? _generatingPractice;
  bool _generatingDaily = false;
  bool _generatingSamurai = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _chapter = (widget.store.nextCareerLevelNumber - 1) ~/ _chapterSize + 1;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('career')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: const DuelAssetIcon(DuelAsset.lightbulb, size: 18),
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
        final nextNumber = widget.store.nextCareerLevelNumber;
        final nextLevel = CareerCatalog.levelAt(nextNumber);
        final chapterStart = (_chapter - 1) * _chapterSize + 1;
        final levels = List<CareerLevel>.generate(
          _chapterSize,
          (index) => CareerCatalog.levelAt(chapterStart + index),
        );
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
                      title: context.tr('career'),
                      subtitle: context.tr('career_intro'),
                      icon: DuelAsset.homeCareerRelic,
                      trailing: context.tr('completed_levels', <Object>[
                        widget.store.completedCareerLevelCount,
                      ]),
                    ),
                    const SizedBox(height: 14),
                    _NextLevelCard(
                      level: nextLevel,
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
                                        _chapter =
                                            (nextNumber - 1) ~/ _chapterSize + 1;
                                      }),
                                child: Text(
                                  context.tr('level_title', <Object>[
                                    context.strings.difficultyLabel(
                                      nextLevel.difficulty,
                                    ),
                                    nextNumber,
                                  ]),
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
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 230,
                            mainAxisExtent: 142,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemBuilder: (context, index) {
                        final level = levels[index];
                        return _LevelCard(
                          level: level,
                          progress: widget.store.progressForCareerLevel(
                            level.number,
                          ),
                          unlocked: widget.store.isCareerLevelUnlocked(
                            level.number,
                          ),
                          current: level.number == nextNumber,
                          loading: _generatingLevel == level.number,
                          onTap:
                              widget.store.isCareerLevelUnlocked(level.number) &&
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
    while (mounted) {
      if (!widget.store.isCareerLevelUnlocked(level.number)) return;
      setState(() => _generatingLevel = level.number);
      final puzzle = await Future<SudokuPuzzle>(
        () => CareerCatalog.puzzleFor(level),
      );
      if (!mounted) return;
      setState(() => _generatingLevel = null);
      final wasCompleted = widget.store.isCompleted(level.id);
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
                ({
                  required seconds,
                  required mistakes,
                  required hints,
                }) async {
                  await widget.store.recordResult(
                    puzzleId: level.id,
                    seconds: seconds,
                    mistakes: mistakes,
                    hints: hints,
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
        _chapter =
            (widget.store.nextCareerLevelNumber - 1) ~/ _chapterSize + 1;
      });
      if (result != EnhancedGameExit.next) return;
      level = CareerCatalog.levelAt(level.number + 1);
    }
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
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
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
              ({
                required seconds,
                required mistakes,
                required hints,
              }) async {
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
              ({
                required seconds,
                required mistakes,
                required hints,
              }) async {
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
    return Card(
      color: const Color(0xFF101B20).withValues(alpha: .94),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            DuelAssetIcon(icon, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      trailing!,
                      style: const TextStyle(
                        color: Color(0xFFFFC94D),
                        fontWeight: FontWeight.w900,
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

class _NextLevelCard extends StatelessWidget {
  const _NextLevelCard({
    required this.level,
    required this.loading,
    required this.onTap,
  });

  final CareerLevel level;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _difficultyAccent(level.difficulty);
    return Card(
      color: accent.withValues(alpha: .16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 48,
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(color: accent),
                      )
                    : Icon(Icons.play_arrow_rounded, color: accent, size: 42),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('continue_action'),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      context.tr('level_title', <Object>[
                        context.strings.difficultyLabel(level.difficulty),
                        level.number,
                      ]),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: accent),
            ],
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
    return Card(
      color: const Color(0xFF101B20).withValues(alpha: .95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: current
              ? accent
              : accent.withValues(alpha: unlocked ? .28 : .10),
          width: current ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                            unlocked
                                ? Icons.grid_4x4_rounded
                                : Icons.lock_outline_rounded,
                            color: unlocked
                                ? accent
                                : Colors.white.withValues(alpha: .36),
                          ),
                  ),
                  const Spacer(),
                  if (progress != null)
                    Row(
                      children: List<Widget>.generate(
                        3,
                        (index) => Icon(
                          index < progress!.stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 17,
                          color: const Color(0xFFFFC94D),
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                context.tr('level_title', <Object>[
                  context.strings.difficultyLabel(level.difficulty),
                  level.number,
                ]),
                maxLines: 1,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unlocked
                      ? accent.withValues(alpha: .9)
                      : Colors.white.withValues(alpha: .34),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
    return Card(
      color: const Color(0xFF101B20).withValues(alpha: .95),
      child: ListTile(
        minTileHeight: 76,
        onTap: onTap,
        leading: SizedBox.square(
          dimension: 48,
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: accent),
                )
              : Icon(icon, color: accent, size: 32),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: .66)),
        ),
        trailing: Icon(Icons.arrow_forward_rounded, color: accent),
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
