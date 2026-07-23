import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../domain/sudoku.dart';
import '../game/game_screen.dart';

class CareerScreen extends StatefulWidget {
  const CareerScreen({super.key, required this.store});
  final LocalProgressStore store;

  @override
  State<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends State<CareerScreen> {
  SudokuDifficulty _difficulty = SudokuDifficulty.beginner;

  @override
  Widget build(BuildContext context) {
    final puzzles = PuzzleCatalog.careerPuzzles
        .where((puzzle) => puzzle.difficulty == _difficulty)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Kariyer')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text(
              'En kolaydan başlayıp adım adım ilerle.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final difficulty in SudokuDifficulty.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(difficulty.label),
                        selected: difficulty == _difficulty,
                        onSelected: (_) =>
                            setState(() => _difficulty = difficulty),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisExtent: 152,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: puzzles.length,
              itemBuilder: (context, index) {
                final puzzle = puzzles[index];
                final progress = widget.store.progressFor(puzzle.id);
                final unlocked =
                    index == 0 ||
                    widget.store.isCompleted(puzzles[index - 1].id);
                return _LevelCard(
                  puzzle: puzzle,
                  progress: progress,
                  unlocked: unlocked,
                  onTap: unlocked ? () => _openPuzzle(puzzle) : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPuzzle(SudokuPuzzle puzzle) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          puzzle: puzzle,
          onCompleted:
              ({required seconds, required mistakes, required hints}) =>
                  widget.store.recordResult(
                    puzzleId: puzzle.id,
                    seconds: seconds,
                    mistakes: mistakes,
                    hints: hints,
                  ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.puzzle,
    required this.progress,
    required this.unlocked,
    required this.onTap,
  });
  final SudokuPuzzle puzzle;
  final LevelProgress? progress;
  final bool unlocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: unlocked
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    child: Icon(unlocked ? Icons.grid_4x4 : Icons.lock_outline),
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
                          size: 20,
                          color: scheme.tertiary,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                puzzle.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                !unlocked
                    ? 'Önceki seviyeyi tamamla'
                    : progress == null
                    ? 'Yeni seviye'
                    : 'En iyi: ${formatDuration(progress!.bestSeconds)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
