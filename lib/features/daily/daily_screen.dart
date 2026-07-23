import 'package:flutter/material.dart';

import '../../data/puzzle_catalog.dart';
import '../../localization/app_strings.dart';
import '../game/game_screen.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GameScreen(
      puzzle: PuzzleCatalog.dailyPuzzle(DateTime.now()),
      completionTitle: context.tr('today_puzzle_completed'),
    );
  }
}
