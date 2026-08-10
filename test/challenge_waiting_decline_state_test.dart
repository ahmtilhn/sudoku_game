import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/features/social/challenge_waiting_screen.dart';

void main() {
  test('declined challenge has an exact declined terminal state', () {
    expect(
      challengeWaitingEndReasonForStatus('declined'),
      ChallengeWaitingEndReason.declined,
    );
  });

  test('expired challenge has an exact expired terminal state', () {
    expect(
      challengeWaitingEndReasonForStatus('expired'),
      ChallengeWaitingEndReason.expired,
    );
  });

  test('cancelled challenge has a separate cancelled terminal state', () {
    expect(
      challengeWaitingEndReasonForStatus('cancelled'),
      ChallengeWaitingEndReason.cancelled,
    );
  });

  test('pending and accepted challenges remain non-terminal', () {
    expect(challengeWaitingEndReasonForStatus('pending'), isNull);
    expect(challengeWaitingEndReasonForStatus('accepted'), isNull);
  });

  test('legacy fallback still separates decline from expiry', () {
    expect(
      inferMissingChallengeEndReason(secondsLeft: 120),
      ChallengeWaitingEndReason.declined,
    );
    expect(
      inferMissingChallengeEndReason(secondsLeft: 0),
      ChallengeWaitingEndReason.expired,
    );
  });
}
