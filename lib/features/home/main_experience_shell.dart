import 'package:flutter/material.dart';

import '../../data/fantasy_sudoku_catalog.dart';
import '../../data/local_progress_store.dart';
import '../../localization/ux_copy.dart';
import '../game/enhanced_game_screen.dart';
import 'ux_root_screen.dart';

class MainExperienceShell extends StatelessWidget {
  const MainExperienceShell({super.key, required this.store});

  final LocalProgressStore store;

  int _dailySeed(DateTime now) => now.year * 10000 + now.month * 100 + now.day;

  Future<void> _openFantasy(BuildContext context) async {
    final puzzle = FantasySudokuCatalog.puzzleForSeed(_dailySeed(DateTime.now()));
    await Navigator.of(context).push<EnhancedGameExit>(
      MaterialPageRoute(
        builder: (gameContext) => EnhancedGameScreen(
          puzzle: puzzle,
          store: store,
          mistakeLimit: null,
          showNextAction: false,
          completionTitle: UxCopy.fantasyTitle(gameContext),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: UxRootScreen(store: store),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Semantics(
        button: true,
        label: UxCopy.fantasyTitle(context),
        child: FloatingActionButton.extended(
          heroTag: 'fantasy-16-launcher',
          key: const ValueKey<String>('fantasy-16-launcher'),
          onPressed: () => _openFantasy(context),
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text(
            '16×16 · A–G',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}
