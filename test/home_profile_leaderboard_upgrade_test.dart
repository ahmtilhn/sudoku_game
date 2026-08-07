import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home uses premium scene artwork and exposes leaderboards', () {
    final source = File(
      'lib/features/home/professional_home_screen.dart',
    ).readAsStringSync();

    for (final asset in <String>[
      'DuelAsset.homePlayScene',
      'DuelAsset.homeDuelScene',
      'DuelAsset.homeCareerScene',
      'DuelAsset.homeFriendsScene',
      'DuelAsset.homeStoreScene',
      'DuelAsset.homeProfileScene',
      'DuelAsset.dailyRewardPro',
      'DuelAsset.walletCoinStackPro',
      'DuelAsset.leaderboardCrownPro',
    ]) {
      expect(source, contains(asset));
    }
    expect(source, contains('LeaderboardsScreen'));
    expect(source, contains('localAvatarBytes: platformPlayer?.avatarBytes'));
  });

  test('profile cards stay compact and expose leaderboard entry', () {
    final source = File(
      'lib/features/social/profile_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains('mainAxisExtent: 84'));
    expect(source, contains('mainAxisExtent: 88'));
    expect(source, contains('LeaderboardsScreen'));
    expect(source, contains('localAvatarBytes: avatarBytes'));
  });

  test('daily reminders follow system permission without settings toggle', () {
    final service = File(
      'lib/services/reminder_notification_service.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/settings/ux_settings_screen.dart',
    ).readAsStringSync();

    expect(service, contains('syncWithSystemPermission'));
    expect(service, contains('requestNotificationsPermission'));
    expect(service, contains('requestPermissions(alert: true'));
    expect(service, isNot(contains('_enabledKey')));
    expect(settings, isNot(contains('ReminderNotificationService')));
  });

  test('platform identity carries native avatar bytes on Android and iOS', () {
    final dart = File(
      'lib/services/platform_game_services.dart',
    ).readAsStringSync();
    final android = File(
      'android/app/src/main/kotlin/com/devoviastudio/sudoku/MainActivity.kt',
    ).readAsStringSync();
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(dart, contains('avatarBytesBase64'));
    expect(dart, contains('Uint8List? get avatarBytes'));
    expect(android, contains('localAvatarBytesBase64'));
    expect(android, contains('"avatarBytesBase64"'));
    expect(ios, contains('loadPhoto(for: .small)'));
    expect(ios, contains('payload["avatarBytesBase64"]'));
  });

  test('duel fee copy describes entry fee and winner pot separately', () {
    final source = File(
      'lib/features/duel/matchmaking_screen.dart',
    ).readAsStringSync();

    expect(source, contains("context.tr('entry_fee')"));
    expect(source, contains("context.tr('winner_pot')"));
    expect(source, isNot(contains("'$fee → $pot'")));
  });

  test('outcome header uses dedicated victory and defeat trophies', () {
    final source = File('lib/widgets/ux_feedback.dart').readAsStringSync();

    expect(source, contains('DuelAsset.resultVictoryTrophyPro'));
    expect(source, contains('DuelAsset.resultDefeatTrophyPro'));
  });

  test('leaderboards show own rank before opening platform boards', () {
    final source = File(
      'lib/features/duel/leaderboards_screen.dart',
    ).readAsStringSync();

    expect(source, contains("mode: 'around_me'"));
    expect(source, contains("current?['rank']"));
    expect(source, contains('_platform.show(scope)'));
    expect(source, contains('UxStatePanel.error'));
  });
}
