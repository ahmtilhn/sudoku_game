import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/player_profile_service.dart';

void main() {
  test('profile preferences tolerate backend scalar variants', () {
    final profile = PlayerProfilePreferences.fromJson(<String, dynamic>{
      'publicId': 'ABCD1234',
      'username': 'pilot',
      'displayName': 'Sudoku Pilot',
      'profileConfirmed': 1,
      'discoverable': '0',
      'nameSource': 'game_center',
      'rating': '1012',
      'gamesPlayed': '7',
      'wins': 3.0,
      'platformConnected': 'true',
    });

    expect(profile.profileConfirmed, isTrue);
    expect(profile.discoverable, isFalse);
    expect(profile.rating, 1012);
    expect(profile.gamesPlayed, 7);
    expect(profile.wins, 3);
    expect(profile.platformConnected, isTrue);
  });
}
