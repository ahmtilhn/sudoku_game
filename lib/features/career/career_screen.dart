import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/ads_service.dart';
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
                    label: Text('${widget.store.coins}'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
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
                progress: widget.store.progressFor('career-${difficulty.name}'),
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
    );
  }

  Future<void> _startRandomPuzzle(SudokuDifficulty difficulty) async {
    setState(() => _generatingDifficulty = difficulty);
    final puzzle = await Future<SudokuPuzzle>(() {
      return PuzzleCatalog.generatePuzzle(difficulty);
    });
    if (!mounted) return;
    setState(() => _generatingDifficulty = null);

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (gameContext) => GameScreen(
          puzzle: puzzle,
          mistakeLimit: 3,
          coinContinueCost: 25,
          onCoinContinue: widget.store.spendCoins,
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
                await widget.store.addCoins(10);
              },
        ),
      ),
    );
    if (mounted) setState(() {});
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
