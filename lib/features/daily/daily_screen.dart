import 'package:flutter/material.dart';

import '../../data/puzzle_catalog.dart';
import '../game/game_screen.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GameScreen(
      puzzle: PuzzleCatalog.dailyPuzzle(DateTime.now()),
      completionTitle: 'Bugünün bulmacası tamamlandı!',
    );
  }
}
