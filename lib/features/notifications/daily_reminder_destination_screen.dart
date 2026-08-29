import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../data/puzzle_catalog.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/platform_game_services.dart';
import '../game/enhanced_game_screen.dart';

/// Notification-only entry point for the daily puzzle.
///
/// This intentionally reuses the same daily puzzle ID and completion bookkeeping
/// as Career > Practice without changing that screen or any online game flow.
class DailyReminderDestinationScreen extends StatefulWidget {
  const DailyReminderDestinationScreen({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<DailyReminderDestinationScreen> createState() =>
      _DailyReminderDestinationScreenState();
}

class _DailyReminderDestinationScreenState
    extends State<DailyReminderDestinationScreen> {
  late Future<SudokuPuzzle> _puzzle;

  @override
  void initState() {
    super.initState();
    _puzzle = _loadPuzzle();
  }

  Future<SudokuPuzzle> _loadPuzzle() =>
      Future<SudokuPuzzle>(() => PuzzleCatalog.dailyPuzzle(DateTime.now()));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SudokuPuzzle>(
      future: _puzzle,
      builder: (context, snapshot) {
        final puzzle = snapshot.data;
        if (puzzle != null) {
          return EnhancedGameScreen(
            puzzle: puzzle,
            store: widget.store,
            showNextAction: false,
            onCompleted:
                ({required seconds, required mistakes, required hints}) async {
                  await widget.store.recordResult(
                    puzzleId: puzzle.id,
                    seconds: seconds,
                    mistakes: mistakes,
                    hints: hints,
                  );
                  await _claimEligibleAchievements();
                },
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('matchmaking_start_failed'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          setState(() => _puzzle = _loadPuzzle());
                        },
                        child: Text(context.tr('try_again')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Future<void> _claimEligibleAchievements() async {
    try {
      if (await PlatformGameServices.instance.refreshAuthentication()) {
        await PlatformGameServices.instance.unlockAchievement();
      }
    } catch (error) {
      debugPrint('Platform daily notification achievement unlock failed: $error');
    }

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
        await EconomyService.instance.claimAchievement(achievement);
      } catch (error) {
        debugPrint(
          'Daily notification achievement claim skipped for $achievement: $error',
        );
      }
    }
  }
}
