import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/career_catalog.dart';
import '../../data/game_session_store.dart';
import '../../data/local_progress_store.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/platform_game_services.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
import '../game/enhanced_game_screen.dart';

class CareerScreen extends StatefulWidget {
  const CareerScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends State<CareerScreen> {
  final EconomyService _economy = EconomyService.instance;
  final GameSessionStore _sessionStore = GameSessionStore.instance;

  String? _generatingLevelId;
  int _selectedChapter = 1;
  ActiveGameSessionMetadata? _activeSession;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_onEconomyChanged);
    _economy.initialize();
    unawaited(_loadActiveSession());
  }

  @override
  void dispose() {
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadActiveSession() async {
    final session = await _sessionStore.latest();
    if (!mounted) return;
    setState(() => _activeSession = session);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait<void>(<Future<void>>[
                _economy.refresh(),
                _loadActiveSession(),
              ]);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth >= 920 ? 820.0 : 720.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: AnimatedBuilder(
                      animation: widget.store,
                      builder: (context, _) {
                        final currentLevel = CareerCatalog.firstPlayable(
                          widget.store.isCompleted,
                        );
                        final activeLevel = _activeSession == null
                            ? null
                            : CareerCatalog.byId(_activeSession!.puzzleId);
                        final selectedLevels = CareerCatalog.chapterLevels(
                          _selectedChapter,
                        );
                        final completedLevels = CareerCatalog.levels
                            .where(
                              (level) => widget.store.isCompleted(level.id),
                            )
                            .length;
                        final totalStars = CareerCatalog.levels.fold<int>(
                          0,
                          (total, level) =>
                              total +
                              (widget.store.progressFor(level.id)?.stars ?? 0),
                        );

                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          children: [
                            InPageHeader(
                              title: context.tr('career'),
                              actions: [
                                _ResourceChip(
                                  asset: DuelAsset.lightbulb,
                                  value: '${widget.store.hints}',
                                  color: const Color(0xFF29D398),
                                ),
                                const SizedBox(width: 6),
                                _ResourceChip(
                                  asset: DuelAsset.coin,
                                  value:
                                      _economy.loading &&
                                          _economy.wallet == null
                                      ? '...'
                                      : '${_economy.balance}',
                                  color: const Color(0xFF3AA9FF),
                                ),
                              ],
                            ),
                            _CareerIntroPanel(
                              completedLevels: completedLevels,
                              totalLevels: CareerCatalog.levels.length,
                              totalStars: totalStars,
                              currentLevel: currentLevel,
                            ),
                            if (activeLevel != null &&
                                _activeSession != null) ...[
                              const SizedBox(height: 14),
                              _ResumeCareerCard(
                                level: activeLevel,
                                elapsedSeconds: _activeSession!.elapsedSeconds,
                                generating:
                                    _generatingLevelId == activeLevel.id,
                                onTap: _generatingLevelId == null
                                    ? () => _startLevel(activeLevel)
                                    : null,
                              ),
                            ],
                            const SizedBox(height: 20),
                            _ChapterSelector(
                              selectedChapter: _selectedChapter,
                              store: widget.store,
                              onSelected: (chapter) {
                                setState(() => _selectedChapter = chapter);
                              },
                            ),
                            const SizedBox(height: 14),
                            _ChapterSummary(
                              levels: selectedLevels,
                              store: widget.store,
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, gridConstraints) {
                                final columns = gridConstraints.maxWidth >= 620
                                    ? 2
                                    : 1;
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: selectedLevels.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        mainAxisExtent: 154,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                      ),
                                  itemBuilder: (context, index) {
                                    final level = selectedLevels[index];
                                    final progress = widget.store.progressFor(
                                      level.id,
                                    );
                                    final unlocked = CareerCatalog.isUnlocked(
                                      level,
                                      widget.store.isCompleted,
                                    );
                                    return _CareerLevelCard(
                                      level: level,
                                      progress: progress,
                                      unlocked: unlocked,
                                      current: currentLevel?.id == level.id,
                                      generating:
                                          _generatingLevelId == level.id,
                                      onTap:
                                          unlocked && _generatingLevelId == null
                                          ? () => _startLevel(level)
                                          : null,
                                    );
                                  },
                                );
                              },
                            ),
                            if (completedLevels ==
                                CareerCatalog.levels.length) ...[
                              const SizedBox(height: 18),
                              _CareerCompletePanel(
                                completedLevels: completedLevels,
                                totalStars: totalStars,
                              ),
                            ],
                            if (_economy.error != null) ...[
                              const SizedBox(height: 14),
                              _InlineError(message: _economy.error!),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startLevel(CareerLevel level) async {
    if (_generatingLevelId != null) return;
    setState(() => _generatingLevelId = level.id);

    SudokuPuzzle puzzle;
    try {
      puzzle = await Future<SudokuPuzzle>(() => CareerCatalog.puzzleFor(level));
    } catch (_) {
      if (!mounted) return;
      setState(() => _generatingLevelId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('matchmaking_start_failed'))),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _generatingLevelId = null);
    final wasCompleted = widget.store.isCompleted(level.id);

    var didComplete = false;
    await Navigator.of(context).push<EnhancedGameExit>(
      MaterialPageRoute(
        builder: (gameContext) => EnhancedGameScreen(
          puzzle: puzzle,
          store: widget.store,
          completionTitle: _levelTitle(gameContext, level),
          mistakeLimit: 3,
          onCompleted:
              ({required seconds, required mistakes, required hints}) async {
                didComplete = true;
                await widget.store.recordResult(
                  puzzleId: level.id,
                  seconds: seconds,
                  mistakes: mistakes,
                  hints: hints,
                );
                await _claimEligibleAchievements();
              },
        ),
      ),
    );

    if (!mounted) return;
    await _loadActiveSession();
    if (!mounted || !didComplete) return;

    final firstCompletion = !wasCompleted;
    if (firstCompletion && level.hintReward > 0) {
      await widget.store.addHints(level.hintReward);
    }
    if (!mounted) return;

    final nextLevel = CareerCatalog.nextOf(level);
    if (nextLevel != null) {
      setState(() => _selectedChapter = nextLevel.chapter);
    }

    final message = firstCompletion && level.hintReward > 0
        ? '${context.tr('congratulations')} '
              '${context.tr('hints_count', <Object>[level.hintReward])}'
        : nextLevel != null
        ? '${context.tr('new_level')}: ${_levelTitle(context, nextLevel)}'
        : context.tr('congratulations');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );

    await _showCareerRewardOffer();
  }

  Future<void> _claimEligibleAchievements() async {
    await _unlockPlatformFirstGrid();
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
      try {
        await _economy.claimAchievement(achievement);
      } catch (error) {
        debugPrint('Achievement claim skipped for $achievement: $error');
      }
    }
  }

  Future<void> _unlockPlatformFirstGrid() async {
    try {
      if (await PlatformGameServices.instance.refreshAuthentication()) {
        await PlatformGameServices.instance.unlockAchievement();
      }
    } catch (error) {
      debugPrint('Platform first-grid achievement unlock failed: $error');
    }
  }

  Future<void> _showCareerRewardOffer() async {
    if (_economy.noAds) return;
    final watch = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111C20),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            20 + MediaQuery.viewPaddingOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DuelAssetIcon(DuelAsset.video, size: 42),
              const SizedBox(height: 10),
              Text(
                context.tr('earn_career_ad_coin', const <Object>[25]),
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('career_ad_reward_body'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: .72)),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const DuelAssetIcon(DuelAsset.video, size: 20),
                  label: Text(
                    context.tr('watch_and_earn_coin', const <Object>[25]),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(context.tr('skip')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (watch != true || !mounted) return;
    final rewarded = await _economy.claimCareerRewardedInterstitial();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          rewarded
              ? context.tr('coin_added_wallet', const <Object>[25])
              : context.tr('rewarded_ad_unavailable'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ResourceChip extends StatelessWidget {
  const _ResourceChip({
    required this.asset,
    required this.value,
    required this.color,
  });

  final String asset;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuelAssetIcon(asset, size: 16, color: color),
            const SizedBox(width: 5),
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
      ),
    );
  }
}

class _CareerIntroPanel extends StatelessWidget {
  const _CareerIntroPanel({
    required this.completedLevels,
    required this.totalLevels,
    required this.totalStars,
    required this.currentLevel,
  });

  final int completedLevels;
  final int totalLevels;
  final int totalStars;
  final CareerLevel? currentLevel;

  @override
  Widget build(BuildContext context) {
    final progress = totalLevels == 0 ? 0.0 : completedLevels / totalLevels;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF19272B).withValues(alpha: .94),
            const Color(0xFF071014).withValues(alpha: .94),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .25),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const DuelAssetIcon(DuelAsset.homeCareerRelic, size: 76),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('career'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        context.tr('career_intro'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: .08),
                color: const Color(0xFFFFC94D),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CareerStat(
                    asset: DuelAsset.trophy,
                    value: '$completedLevels / $totalLevels',
                    label: context.tr('completed_levels', <Object>[
                      completedLevels,
                    ]),
                    color: const Color(0xFFFFC94D),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CareerStat(
                    icon: Icons.star_rounded,
                    value: '$totalStars / ${totalLevels * 3}',
                    label: currentLevel == null
                        ? context.tr('congratulations')
                        : _levelTitle(context, currentLevel!),
                    color: const Color(0xFF29D398),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CareerStat extends StatelessWidget {
  const _CareerStat({
    this.asset,
    this.icon,
    required this.value,
    required this.label,
    required this.color,
  }) : assert(asset != null || icon != null);

  final String? asset;
  final IconData? icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (asset != null)
              DuelAssetIcon(asset!, size: 22, color: color)
            else
              Icon(icon, size: 22, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .58),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeCareerCard extends StatelessWidget {
  const _ResumeCareerCard({
    required this.level,
    required this.elapsedSeconds,
    required this.generating,
    required this.onTap,
  });

  final CareerLevel level;
  final int elapsedSeconds;
  final bool generating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _difficultyAccent(level.difficulty);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: .17),
                const Color(0xFF071014).withValues(alpha: .88),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: .42)),
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: .14),
                  border: Border.all(color: accent.withValues(alpha: .38)),
                ),
                child: SizedBox.square(
                  dimension: 54,
                  child: generating
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: accent,
                          ),
                        )
                      : const DuelAssetIcon(
                          DuelAsset.grid,
                          size: 30,
                          color: Colors.white,
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('continue_action'),
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _levelTitle(context, level),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDuration(elapsedSeconds),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              DuelAssetIcon(DuelAsset.arrowForward, size: 22, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterSelector extends StatelessWidget {
  const _ChapterSelector({
    required this.selectedChapter,
    required this.store,
    required this.onSelected,
  });

  final int selectedChapter;
  final LocalProgressStore store;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (
            var chapter = 1;
            chapter <= SudokuDifficulty.values.length;
            chapter++
          ) ...[
            _ChapterChip(
              chapter: chapter,
              selected: chapter == selectedChapter,
              completed: CareerCatalog.chapterLevels(
                chapter,
              ).where((level) => store.isCompleted(level.id)).length,
              onTap: () => onSelected(chapter),
            ),
            if (chapter < SudokuDifficulty.values.length)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ChapterChip extends StatelessWidget {
  const _ChapterChip({
    required this.chapter,
    required this.selected,
    required this.completed,
    required this.onTap,
  });

  final int chapter;
  final bool selected;
  final int completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final difficulty = SudokuDifficulty.values[chapter - 1];
    final accent = _difficultyAccent(difficulty);
    return Semantics(
      selected: selected,
      button: true,
      label: context.strings.difficultyLabel(difficulty),
      child: Material(
        color: selected
            ? accent.withValues(alpha: .18)
            : const Color(0xFF071014).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: accent.withValues(alpha: selected ? .62 : .24),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.strings.difficultyLabel(difficulty),
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 7),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    child: Text(
                      '$completed/10',
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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

class _ChapterSummary extends StatelessWidget {
  const _ChapterSummary({required this.levels, required this.store});

  final List<CareerLevel> levels;
  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    final difficulty = levels.first.difficulty;
    final accent = _difficultyAccent(difficulty);
    final completed = levels
        .where((level) => store.isCompleted(level.id))
        .length;
    final stars = levels.fold<int>(
      0,
      (total, level) => total + (store.progressFor(level.id)?.stars ?? 0),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .12),
              ),
              child: SizedBox.square(
                dimension: 44,
                child: DuelAssetIcon(DuelAsset.grid, size: 25, color: accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.strings.difficultyLabel(difficulty),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: completed / levels.length,
                      backgroundColor: Colors.white.withValues(alpha: .07),
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$completed/${levels.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFC94D),
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$stars/${levels.length * 3}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CareerLevelCard extends StatelessWidget {
  const _CareerLevelCard({
    required this.level,
    required this.progress,
    required this.unlocked,
    required this.current,
    required this.generating,
    required this.onTap,
  });

  final CareerLevel level;
  final LevelProgress? progress;
  final bool unlocked;
  final bool current;
  final bool generating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _difficultyAccent(level.difficulty);
    final completed = progress != null;
    final borderColor = !unlocked
        ? Colors.white.withValues(alpha: .10)
        : current
        ? accent.withValues(alpha: .72)
        : completed
        ? const Color(0xFFFFC94D).withValues(alpha: .45)
        : accent.withValues(alpha: .28);

    final semanticStatus = !unlocked
        ? context.tr('complete_previous_level')
        : completed
        ? context.tr('completed_levels', const <Object>[1])
        : context.tr('new_level');

    return Semantics(
      button: unlocked,
      enabled: unlocked,
      label: '${_levelTitle(context, level)}. $semanticStatus',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(
                    0xFF172226,
                  ).withValues(alpha: unlocked ? .82 : .48),
                  const Color(
                    0xFF071014,
                  ).withValues(alpha: unlocked ? .94 : .70),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: borderColor),
              boxShadow: current
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: .12),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: unlocked
                            ? accent.withValues(alpha: .14)
                            : Colors.white.withValues(alpha: .05),
                        border: Border.all(
                          color: unlocked
                              ? accent.withValues(alpha: .35)
                              : Colors.white.withValues(alpha: .10),
                        ),
                      ),
                      child: SizedBox.square(
                        dimension: 42,
                        child: Center(
                          child: generating
                              ? SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: accent,
                                  ),
                                )
                              : !unlocked
                              ? Icon(
                                  Icons.lock_rounded,
                                  color: Colors.white.withValues(alpha: .42),
                                  size: 20,
                                )
                              : Text(
                                  '${level.number}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _levelTitle(context, level),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unlocked
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: .45),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${level.size}×${level.size}',
                            style: TextStyle(
                              color: unlocked
                                  ? accent.withValues(alpha: .86)
                                  : Colors.white.withValues(alpha: .34),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (completed)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List<Widget>.generate(
                          3,
                          (index) => Icon(
                            index < progress!.stars
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: index < progress!.stars
                                ? const Color(0xFFFFC94D)
                                : Colors.white.withValues(alpha: .22),
                            size: 17,
                          ),
                        ),
                      )
                    else if (current)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accent.withValues(alpha: .30),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Text(
                            context.tr('new_level'),
                            style: TextStyle(
                              color: accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                if (!unlocked)
                  Text(
                    context.tr('complete_previous_level'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .38),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else if (completed)
                  Row(
                    children: [
                      DuelAssetIcon(
                        DuelAsset.trophy,
                        size: 15,
                        color: const Color(0xFFFFC94D),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          context.tr('best_time', <Object>[
                            formatDuration(progress!.bestSeconds),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .66),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      DuelAssetIcon(
                        DuelAsset.arrowForward,
                        size: 18,
                        color: accent,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(
                        Icons.favorite_border_rounded,
                        color: accent,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          context.tr('three_mistake_rule'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .58),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      DuelAssetIcon(
                        DuelAsset.arrowForward,
                        size: 18,
                        color: accent,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CareerCompletePanel extends StatelessWidget {
  const _CareerCompletePanel({
    required this.completedLevels,
    required this.totalStars,
  });

  final int completedLevels;
  final int totalStars;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFC94D).withValues(alpha: .20),
            const Color(0xFF071014).withValues(alpha: .90),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .48),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const DuelAssetIcon(DuelAsset.trophy, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('congratulations'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${context.tr('completed_levels', <Object>[completedLevels])} · '
                    '★ $totalStars/${completedLevels * 3}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .70),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFF5C7A).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF5C7A).withValues(alpha: .28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8FA3)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _difficultyAccent(SudokuDifficulty difficulty) => switch (difficulty) {
  SudokuDifficulty.beginner => const Color(0xFF29D398),
  SudokuDifficulty.easy => const Color(0xFF3AA9FF),
  SudokuDifficulty.medium => const Color(0xFFFFC94D),
  SudokuDifficulty.hard => const Color(0xFFFF8A3D),
  SudokuDifficulty.expert => const Color(0xFFFF5C7A),
};

String _levelTitle(BuildContext context, CareerLevel level) {
  return context.tr('level_title', <Object>[
    context.strings.difficultyLabel(level.difficulty),
    level.chapterLevel,
  ]);
}
