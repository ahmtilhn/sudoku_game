import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/platform_profile_policy.dart';

void main() {
  group('PlatformProfilePolicy', () {
    test('confirmed custom nickname is never overwritten', () {
      expect(
        PlatformProfilePolicy.decideNameUpdate(
          profileConfirmed: true,
          currentNameSource: 'custom',
          currentDisplayName: 'My Sudoku Name',
          platformDisplayName: 'Google Player',
        ),
        PlatformProfileNameDecision.preserveCustom,
      );
    });

    test('unconfirmed profile may adopt platform display name', () {
      expect(
        PlatformProfilePolicy.decideNameUpdate(
          profileConfirmed: false,
          currentNameSource: 'generated',
          currentDisplayName: 'Sudoku Player',
          platformDisplayName: 'Google Player',
        ),
        PlatformProfileNameDecision.adoptPlatform,
      );
    });

    test('unchanged or empty platform name keeps current value', () {
      expect(
        PlatformProfilePolicy.decideNameUpdate(
          profileConfirmed: false,
          currentNameSource: 'google_play_games',
          currentDisplayName: 'Google Player',
          platformDisplayName: ' Google Player ',
        ),
        PlatformProfileNameDecision.keepCurrent,
      );
      expect(
        PlatformProfilePolicy.decideNameUpdate(
          profileConfirmed: false,
          currentNameSource: 'generated',
          currentDisplayName: 'Sudoku Player',
          platformDisplayName: ' ',
        ),
        PlatformProfileNameDecision.keepCurrent,
      );
    });

    test('avatar accepts only usable HTTPS URLs', () {
      expect(
        PlatformProfilePolicy.normalizedAvatarUrl(
          ' https://example.com/avatar.png ',
        ),
        'https://example.com/avatar.png',
      );
      expect(
        PlatformProfilePolicy.normalizedAvatarUrl('http://example.com/a.png'),
        isNull,
      );
      expect(PlatformProfilePolicy.normalizedAvatarUrl('not-a-url'), isNull);
    });
  });
}
