import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/models/rank_identity_fallback.dart';

void main() {
  test('local rank fallback keeps customization populated', () {
    final profile = buildRankIdentityFallback();

    expect(profile.rankPoints, 0);
    expect(profile.rankName, 'Bronze III');
    expect(profile.availableAvatarCount, 96);
    expect(profile.unlockedFrameKeys, contains('bronze_3'));
    expect(profile.rankRewards, hasLength(15));
    expect(
      profile.rankRewards.fold<int>(0, (sum, reward) => sum + reward.amount),
      12000,
    );
    expect(
      profile.decorations.any(
        (item) =>
            item.achievementId == 'undefeated_50' &&
            item.decorationKey == 'unbeaten_shield_50' &&
            item.rarity == 'legendary',
      ),
      isTrue,
    );
  });

  test('customization and leaderboard do not block their entire UI on network', () {
    final customization = File(
      'lib/features/social/profile_customization_screen.dart',
    ).readAsStringSync();
    final leaderboard = File(
      'lib/features/duel/leaderboards_screen.dart',
    ).readAsStringSync();

    expect(customization, contains('buildRankIdentityFallback'));
    expect(customization, contains('AvatarPresetCatalog.all'));
    expect(customization, contains('TabBarView'));
    expect(customization, contains('3 achievement slots'));
    expect(customization, isNot(contains('_loading ? const Center')));

    expect(leaderboard, contains('buildRankIdentityFallback'));
    expect(leaderboard, contains('Global RP leaderboard'));
    expect(leaderboard, contains('loadLeaderboard('));
    expect(leaderboard, isNot(contains('_loading && _profile == null')));
  });
}
