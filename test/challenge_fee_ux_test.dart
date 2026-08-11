import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/economy_api_client.dart';

void main() {
  test('wallet exposes exact fee for each difficulty', () {
    const wallet = WalletSnapshot(
      balance: 100,
      canEnterOnline: true,
      minimumOnlineBalance: 100,
      entryFees: <String, int>{
        'beginner': 100,
        'easy': 150,
        'medium': 250,
        'hard': 400,
        'expert': 650,
      },
      noAds: false,
      starterGrant: 1000,
      dailyLoginAmount: 50,
      dailyLoginAvailable: true,
      dailyAdAmount: 50,
      dailyAdAvailable: true,
    );

    expect(wallet.canEnterOnline, isTrue);
    expect(wallet.balance >= wallet.entryFeeForDifficulty('beginner'), isTrue);
    expect(wallet.balance >= wallet.entryFeeForDifficulty('expert'), isFalse);
    expect(wallet.winnerPotForDifficulty('expert'), 1300);
  });
}
