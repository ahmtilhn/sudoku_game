import '../../services/online_duel_models.dart';

class DuelPayoutDisplay {
  const DuelPayoutDisplay({
    required this.entryFee,
    required this.pot,
    required this.localPayout,
    required this.opponentPayout,
    required this.refunded,
  });

  final int entryFee;
  final int pot;
  final int localPayout;
  final int opponentPayout;
  final bool refunded;

  factory DuelPayoutDisplay.fromSnapshot(
    OnlineDuelSnapshot snapshot, {
    required int entryFee,
  }) {
    final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
        ? OnlineDuelSeat.b
        : OnlineDuelSeat.a;
    final settlement = snapshot.coinSettlement;
    final fallbackPot = entryFee * 2;
    final refunded = snapshot.winnerSeat == null;
    final pot = settlement != null && settlement.amount > 0
        ? settlement.amount
        : fallbackPot;

    int fallbackFor(OnlineDuelSeat seat) {
      if (refunded) return entryFee;
      return snapshot.winnerSeat == seat ? fallbackPot : 0;
    }

    return DuelPayoutDisplay(
      entryFee: entryFee,
      pot: pot,
      localPayout:
          settlement?.deltas[snapshot.youSeat] ?? fallbackFor(snapshot.youSeat),
      opponentPayout:
          settlement?.deltas[opponentSeat] ?? fallbackFor(opponentSeat),
      refunded: refunded,
    );
  }
}
