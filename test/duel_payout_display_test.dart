import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/features/duel/duel_payout_display.dart';
import 'package:sudoku_game/services/online_duel_models.dart';

void main() {
  test('beginner winner receives full 200 Coin pot and loser receives zero', () {
    final snapshot = _snapshot(
      youSeat: OnlineDuelSeat.a,
      winnerSeat: OnlineDuelSeat.a,
      amount: 200,
      deltas: const {OnlineDuelSeat.a: 200, OnlineDuelSeat.b: 0},
    );
    final payout = DuelPayoutDisplay.fromSnapshot(snapshot, entryFee: 100);

    expect(payout.entryFee, 100);
    expect(payout.pot, 200);
    expect(payout.localPayout, 200);
    expect(payout.opponentPayout, 0);
    expect(payout.refunded, isFalse);
  });

  test('dynamic difficulty payout uses the actual escrow amount', () {
    final snapshot = _snapshot(
      youSeat: OnlineDuelSeat.b,
      winnerSeat: OnlineDuelSeat.a,
      amount: 800,
      deltas: const {OnlineDuelSeat.a: 800, OnlineDuelSeat.b: 0},
    );
    final payout = DuelPayoutDisplay.fromSnapshot(snapshot, entryFee: 400);

    expect(payout.pot, 800);
    expect(payout.localPayout, 0);
    expect(payout.opponentPayout, 800);
  });

  test('draw displays each refunded entry instead of a winner payout', () {
    final snapshot = _snapshot(
      youSeat: OnlineDuelSeat.a,
      winnerSeat: null,
      amount: 0,
      deltas: const {OnlineDuelSeat.a: 150, OnlineDuelSeat.b: 150},
    );
    final payout = DuelPayoutDisplay.fromSnapshot(snapshot, entryFee: 150);

    expect(payout.refunded, isTrue);
    expect(payout.localPayout, 150);
    expect(payout.opponentPayout, 150);
  });
}

OnlineDuelSnapshot _snapshot({
  required OnlineDuelSeat youSeat,
  required OnlineDuelSeat? winnerSeat,
  required int amount,
  required Map<OnlineDuelSeat, int> deltas,
}) {
  return OnlineDuelSnapshot(
    roomId: 'room',
    matchId: 'match',
    mode: 'ranked',
    difficulty: 'beginner',
    status: OnlineDuelStatus.completed,
    youSeat: youSeat,
    players: const {
      OnlineDuelSeat.a: OnlineDuelPlayer(
        publicId: 'a',
        username: 'alice',
        displayName: 'Alice',
        avatarKey: 'default',
        ready: true,
        screenLoaded: true,
        connected: true,
      ),
      OnlineDuelSeat.b: OnlineDuelPlayer(
        publicId: 'b',
        username: 'bob',
        displayName: 'Bob',
        avatarKey: 'default',
        ready: true,
        screenLoaded: true,
        connected: true,
      ),
    },
    puzzle: List<int>.filled(81, 0),
    board: List<int>.filled(81, 0),
    scores: const {OnlineDuelSeat.a: 10, OnlineDuelSeat.b: 0},
    mistakes: const {OnlineDuelSeat.a: 0, OnlineDuelSeat.b: 0},
    correctMoves: const {OnlineDuelSeat.a: 1, OnlineDuelSeat.b: 0},
    timeouts: const {OnlineDuelSeat.a: 0, OnlineDuelSeat.b: 0},
    currentTurnSeat: OnlineDuelSeat.a,
    turnNumber: 1,
    serverTime: DateTime.fromMillisecondsSinceEpoch(0),
    revision: 1,
    winnerSeat: winnerSeat,
    coinSettlement: OnlineDuelCoinSettlement(
      amount: amount,
      winnerSeat: winnerSeat,
      loserSeat: winnerSeat == null
          ? null
          : winnerSeat == OnlineDuelSeat.a
          ? OnlineDuelSeat.b
          : OnlineDuelSeat.a,
      balances: const {OnlineDuelSeat.a: 1000, OnlineDuelSeat.b: 900},
      deltas: deltas,
    ),
  );
}
