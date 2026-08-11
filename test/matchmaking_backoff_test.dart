import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/features/duel/matchmaking_screen.dart';

void main() {
  test(
    'matchmaking fallback polling backs off without delaying first check',
    () {
      expect(matchmakingFallbackDelay(0), const Duration(seconds: 3));
      expect(matchmakingFallbackDelay(1), const Duration(seconds: 5));
      expect(matchmakingFallbackDelay(4), const Duration(seconds: 5));
      expect(matchmakingFallbackDelay(5), const Duration(seconds: 10));
    },
  );
}
