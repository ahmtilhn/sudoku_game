import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../game/game_screen.dart';
import '../game/hint_economy.dart';

class CareerScreen extends StatefulWidget {
  const CareerScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends State<CareerScreen> {
  SudokuDifficulty? _generatingDifficulty;
  final EconomyService _economy = EconomyService.instance;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_onEconomyChanged);
    _economy.initialize();
  }

  @override
  void dispose() {
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.tr('career')),
        actions: [
          AnimatedBuilder(
            animation: widget.store,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Chip(
                    avatar: const DuelAssetIcon(DuelAsset.lightbulb, size: 18),
                    label: Text('${widget.store.hints}'),
                  ),
                  const SizedBox(width: 6),
                  Chip(
                    avatar: const DuelAssetIcon(
                      DuelAsset.coin,
                      size: 18,
                      color: Color(0xFFFFC94D),
                    ),
                    label: Text(
                      _economy.loading && _economy.wallet == null
                          ? '...'
                          : '${_economy.balance}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: AppBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth >= 840 ? 720.0 : 640.0;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: AnimatedBuilder(
                    animation: widget.store,
                    builder: (context, _) => ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        _CareerIntroPanel(
                          completedLevels: widget.store.completedLevelCount,
                        ),
                        const SizedBox(height: 18),
                        for (final difficulty in SudokuDifficulty.values) ...[
                          _DifficultyCard(
                            difficulty: difficulty,
                            clueCount: PuzzleCatalog.targetClueCount(
                              difficulty,
                            ),
                            progress: widget.store.progressFor(
                              'career-${difficulty.name}',
                            ),
                            generating: _generatingDifficulty == difficulty,
                            onTap: _generatingDifficulty == null
                                ? () => _startRandomPuzzle(difficulty)
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
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

  Future<void> _startRandomPuzzle(SudokuDifficulty difficulty) async {
    setState(() => _generatingDifficulty = difficulty);
    final puzzle = await Future<SudokuPuzzle>(() {
      return PuzzleCatalog.generatePuzzle(difficulty);
    });
    if (!mounted) return;
    setState(() => _generatingDifficulty = null);

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (gameContext) => GameScreen(
          puzzle: puzzle,
          mistakeLimit: 3,
          coinContinueCost: 25,
          onCoinContinue: (_) => _economy.spendCareerContinue(),
          onRewardedContinue: AdsService.instance.showRewarded,
          onConsumeHint: () =>
              HintEconomy.consumeOrAcquire(gameContext, widget.store),
          hintBalanceProvider: () => widget.store.hints,
          onCompleted:
              ({required seconds, required mistakes, required hints}) async {
                await widget.store.recordResult(
                  puzzleId: 'career-${difficulty.name}',
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
    if (completed == true) {
      await _showCareerRewardOffer();
    }
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

  Future<void> _showCareerRewardOffer() async {
    if (_economy.noAds) return;
    final watch = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('career_ad_reward_body'),
                textAlign: TextAlign.center,
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
      ),
    );
  }
}

class _CareerIntroPanel extends StatelessWidget {
  const _CareerIntroPanel({required this.completedLevels});

  final int completedLevels;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const DuelAssetIcon(DuelAsset.homeCareerRelic, size: 74),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('career'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.tr('career_random_intro'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _CareerMetaPill(
                        asset: DuelAsset.trophy,
                        text: context.tr('completed_levels', <Object>[
                          completedLevels,
                        ]),
                        color: const Color(0xFFFFC94D),
                      ),
                      _CareerMetaPill(
                        asset: DuelAsset.target,
                        text: context.tr('mistakes_limit_count', <Object>[
                          0,
                          3,
                        ]),
                        color: const Color(0xFF29D398),
                      ),
                    ],
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

class _CareerMetaPill extends StatelessWidget {
  const _CareerMetaPill({
    required this.asset,
    required this.text,
    required this.color,
  });

  final String asset;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuelAssetIcon(asset, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              text,
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

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.difficulty,
    required this.clueCount,
    required this.progress,
    required this.generating,
    required this.onTap,
  });

  final SudokuDifficulty difficulty;
  final int clueCount;
  final LevelProgress? progress;
  final bool generating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (difficulty) {
      SudokuDifficulty.beginner => const Color(0xFF29D398),
      SudokuDifficulty.easy => const Color(0xFF3AA9FF),
      SudokuDifficulty.medium => const Color(0xFFFFC94D),
      SudokuDifficulty.hard => const Color(0xFFFF8A3D),
      SudokuDifficulty.expert => const Color(0xFFFF5C7A),
    };
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF071014).withValues(alpha: .76),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: .30)),
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: .12),
                  border: Border.all(color: accent.withValues(alpha: .36)),
                ),
                child: SizedBox.square(
                  dimension: 58,
                  child: generating
                      ? Padding(
                          padding: const EdgeInsets.all(17),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: accent,
                          ),
                        )
                      : const DuelAssetIcon(
                          DuelAsset.grid,
                          size: 34,
                          color: Colors.white,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.strings.difficultyLabel(difficulty),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      context.tr('random_clue_count', <Object>[clueCount]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.tr('best_time', <Object>[
                          formatDuration(progress!.bestSeconds),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent.withValues(alpha: .88),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DuelAssetIcon(
                DuelAsset.arrowForward,
                color: accent.withValues(alpha: .90),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
