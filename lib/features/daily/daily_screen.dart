import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../localization/app_strings.dart';
import '../game/game_screen.dart';
import '../game/hint_economy.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  Widget build(BuildContext context) {
    return GameScreen(
      puzzle: PuzzleCatalog.dailyPuzzle(DateTime.now()),
      completionTitle: context.tr('today_puzzle_completed'),
      onConsumeHint: () => HintEconomy.consumeOrAcquire(context, store),
      hintBalanceProvider: () => store.hints,
    );
  }
}
