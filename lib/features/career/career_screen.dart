import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
import '../../services/economy_service.dart';
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
      appBar: AppBar(
        title: Text(context.tr('career')),
        actions: [
          AnimatedBuilder(
            animation: widget.store,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Chip(
                    avatar: const Icon(Icons.lightbulb_outline, size: 18),
                    label: Text('${widget.store.hints}'),
                  ),
                  const SizedBox(width: 6),
                  Chip(
                    avatar: const Icon(
                      Icons.monetization_on_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _economy.loading && _economy.wallet == null
                          ? '…'
                          : '${_economy.balance}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
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
                      Text(
                        context.tr('career_random_intro'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr('three_mistake_rule'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final difficulty in SudokuDifficulty.values) ...[
                        _DifficultyCard(
                          difficulty: difficulty,
                          clueCount: PuzzleCatalog.targetClueCount(difficulty),
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
              const Icon(Icons.ondemand_video_rounded, size: 42),
              const SizedBox(height: 10),
              Text(
                'Earn 25 Coin',
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Watch an optional rewarded ad after this completed puzzle.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Watch and earn +25 Coin'),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Skip'),
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
              ? '25 Coin added to your wallet.'
              : 'The reward ad is not available right now.',
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: scheme.primaryContainer,
                child: generating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.casino_outlined),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.strings.difficultyLabel(difficulty),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('random_clue_count', <Object>[clueCount]),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.tr('best_time', <Object>[
                          formatDuration(progress!.bestSeconds),
                        ]),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.play_arrow_rounded, color: scheme.primary, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}
