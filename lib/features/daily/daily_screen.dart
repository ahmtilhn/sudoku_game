import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../localization/app_strings.dart';
import '../game/enhanced_game_screen.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    final puzzle = PuzzleCatalog.dailyPuzzle(DateTime.now());
    return EnhancedGameScreen(
      puzzle: puzzle,
      store: store,
      completionTitle: context.tr('today_puzzle_completed'),
      showNextAction: false,
      onCompleted:
          ({required seconds, required mistakes, required hints}) async {
            await store.recordResult(
              puzzleId: puzzle.id,
              seconds: seconds,
              mistakes: mistakes,
              hints: hints,
            );
          },
    );
  }
}
