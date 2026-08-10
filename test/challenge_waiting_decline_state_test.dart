import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/features/social/challenge_waiting_screen.dart';

void main() {
  test('missing live challenge before expiry is treated as declined', () {
    expect(
      inferMissingChallengeEndReason(secondsLeft: 120),
      ChallengeWaitingEndReason.declined,
    );
  });

  test('missing live challenge after expiry is treated as expired', () {
    expect(
      inferMissingChallengeEndReason(secondsLeft: 0),
      ChallengeWaitingEndReason.expired,
    );
  });
}
