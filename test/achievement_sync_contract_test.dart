import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google Play first win is server-authoritative and explicitly mapped', () {
    final sync = File(
      'lib/services/achievement_sync_service.dart',
    ).readAsStringSync();
    final bridge = File(
      'lib/services/platform_game_services.dart',
    ).readAsStringSync();
    final leaderboard = File(
      'lib/services/platform_leaderboard_service.dart',
    ).readAsStringSync();
    final nativeAndroid = File(
      'android/app/src/main/kotlin/com/devoviastudio/sudoku/MainActivity.kt',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final gamesIds = File(
      'android/app/src/main/res/values/games-ids.xml',
    ).readAsStringSync();

    const id = 'CgkIzMyzm9saEAIQSg';
    expect(gamesIds, contains(id));
    expect(sync, contains("googlePlayFirstWinAchievementId =\n      '$id'"));
    expect(sync, contains("item['id']?.toString() == 'first_win'"));
    expect(
      sync,
      contains('achievementId: googlePlayFirstWinAchievementId'),
    );
    expect(
      bridge,
      contains('if (normalized == null || normalized.isEmpty)'),
    );
    expect(bridge, contains('return Future<bool>.value(false);'));
    expect(nativeAndroid, contains('.unlockImmediate(achievementId)'));
    expect(nativeAndroid, contains('"achievement_submit_failed"'));
    expect(
      leaderboard,
      contains('syncNow(retryForSettlement: true)'),
    );
    expect(main, contains('AchievementSyncService.instance.syncNow()'));
  });

  test('local puzzle completion cannot use an implicit Play achievement ID', () {
    final bridge = File(
      'lib/services/platform_game_services.dart',
    ).readAsStringSync();
    final sync = File(
      'lib/services/achievement_sync_service.dart',
    ).readAsStringSync();

    expect(
      bridge,
      isNot(contains("?: getString(R.string.achievement_first_win)")),
    );
    expect(
      bridge,
      contains('A platform achievement must always be mapped from a server achievement.'),
    );
    expect(
      sync,
      contains('only this\n          // server-authoritative path can use the platform default achievement.'),
    );
  });
}
