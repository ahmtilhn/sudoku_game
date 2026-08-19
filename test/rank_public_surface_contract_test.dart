import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active social and challenge surfaces never render hidden Elo/MMR', () {
    final forbidden = <String, List<String>>{
      'lib/features/social/social_hub_screen.dart': <String>[
        'player.rating',
        'challenge.challenger.rating',
        "tr('rating_value'",
      ],
      'lib/features/social/friend_requests_screen.dart': <String>[
        'player.rating',
        "tr('player_rating_summary'",
      ],
      'lib/features/social/ux_challenge_invitation_screen.dart': <String>[
        'challenge.challenger.rating',
        "tr('rating_value'",
      ],
      'lib/features/social/challenge_waiting_screen.dart': <String>[
        'recipient.rating',
        "tr('rating_value'",
      ],
      'lib/features/social/challenge_invitation_screen.dart': <String>[
        'challenge.challenger.rating',
        "tr('rating_value'",
      ],
    };

    for (final entry in forbidden.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final text in entry.value) {
        expect(
          source.contains(text),
          isFalse,
          reason: '${entry.key} must not render hidden matchmaking MMR via $text',
        );
      }
    }
  });

  test('active challenge/social screens request visible public rank summaries', () {
    for (final path in <String>[
      'lib/features/social/social_hub_screen.dart',
      'lib/features/social/friend_requests_screen.dart',
      'lib/features/social/ux_challenge_invitation_screen.dart',
      'lib/features/social/challenge_waiting_screen.dart',
      'lib/features/social/challenge_invitation_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('loadPublicRankSummary'),
        isTrue,
        reason: '$path must use the public RP identity route',
      );
    }
  });

  test('remote platform avatar keys cannot resolve viewer local platform image', () {
    final source = File('lib/widgets/player_avatar.dart').readAsStringSync();
    expect(source.contains('PlatformGameServices.instance.localPlayer.value'), isFalse);
    expect(source.contains('localAvatarBytes'), isTrue);
    expect(source.contains('remoteApprovedImageUrl'), isTrue);
  });
}
