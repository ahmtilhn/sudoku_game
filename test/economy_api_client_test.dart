import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/economy_api_client.dart';

void main() {
  test('wallet snapshot parses Coin entry and daily reward state', () {
    final wallet = WalletSnapshot.fromJson(<String, dynamic>{
      'balance': 1000,
      'canEnterOnline': true,
      'minimumOnlineBalance': 100,
      'entryFees': <String, dynamic>{
        'beginner': 100,
        'easy': 150,
        'medium': 250,
        'hard': 400,
        'expert': 650,
      },
      'entitlements': <String, dynamic>{'noAds': true},
      'starterGrant': 1000,
      'dailyLogin': <String, dynamic>{'amount': 50, 'available': true},
      'dailyRewardedAd': <String, dynamic>{'amount': 50, 'available': false},
      'nextDailyResetAt': '2026-07-28T00:00:00.000Z',
      'purchaseGranted': true,
      'androidConsumptionHandledByServer': true,
      'androidAcknowledgementHandledByServer': false,
    });

    expect(wallet.balance, 1000);
    expect(wallet.canEnterOnline, isTrue);
    expect(wallet.entryFee, 100);
    expect(wallet.winnerPot, 200);
    expect(wallet.entryFeeForDifficulty('expert'), 650);
    expect(wallet.winnerPotForDifficulty('expert'), 1300);
    expect(wallet.noAds, isTrue);
    expect(wallet.dailyLoginAvailable, isTrue);
    expect(wallet.dailyAdAvailable, isFalse);
    expect(wallet.purchaseGranted, isTrue);
    expect(wallet.androidConsumptionHandledByServer, isTrue);
    expect(wallet.androidAcknowledgementHandledByServer, isFalse);
  });

  test('exactly 100 Coin remains eligible for online play', () {
    final wallet = WalletSnapshot.fromJson(<String, dynamic>{
      'balance': 100,
      'canEnterOnline': true,
      'minimumOnlineBalance': 100,
      'entryFee': 100,
      'starterGrant': 1000,
      'dailyLogin': <String, dynamic>{'amount': 50, 'available': false},
      'dailyRewardedAd': <String, dynamic>{'amount': 50, 'available': false},
    });

    expect(wallet.balance, 100);
    expect(wallet.canEnterOnline, isTrue);
  });

  test('rematch invitation preserves server expiry and room', () {
    final invitation = RematchInvitation.fromJson(<String, dynamic>{
      'id': 'rematch-1',
      'previousMatchId': 'match-1',
      'difficulty': 'easy',
      'status': 'accepted',
      'roomId': 'room-2',
      'createdAt': '2026-07-27T20:00:00.000Z',
      'expiresAt': '2026-07-27T20:00:10.000Z',
      'isSender': true,
      'sender': <String, dynamic>{
        'publicId': 'AAA111',
        'displayName': 'Player A',
      },
      'recipient': <String, dynamic>{
        'publicId': 'BBB222',
        'displayName': 'Player B',
      },
    });

    expect(invitation.status, 'accepted');
    expect(invitation.roomId, 'room-2');
    expect(invitation.sender.displayName, 'Player A');
    expect(invitation.recipient.publicId, 'BBB222');
  });
}
