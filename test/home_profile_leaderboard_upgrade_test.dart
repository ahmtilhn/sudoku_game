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
      'DuelAsset.gift',
      'DuelAsset.coin',
      'DuelAsset.leaderboardCrownPro',
    ]) {
      expect(source, contains(asset));
    }
    expect(source, contains('LeaderboardsScreen'));
    expect(source, contains('localAvatarBytes: platformPlayer?.avatarBytes'));
    expect(
      source,
      contains('constraints: const BoxConstraints(maxWidth: 760)'),
    );
  });

  test('profile cards stay compact and expose leaderboard entry', () {
    final source = File(
      'lib/features/social/profile_hub_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_ProfileTabs'));
    expect(source, contains('_ProfileTabPanel'));
    expect(source, contains('_selectedTab'));
    expect(source, contains('DuelAsset.leaderboardCrownPro'));
    expect(source, contains('LeaderboardsScreen'));
    expect(source, contains('CompetitiveProfileCard'));
    expect(source, contains('_selectedTab = _ProfileTab.leaderboards'));
    expect(source, isNot(contains('WalletHistoryScreen')));
    expect(source, isNot(contains('SocialHubScreen')));
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
    expect(settings, contains('ReminderNotificationService'));
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
    expect(android, contains('avatarBytesBase64'));
    expect(android, contains('downloadAvatarBytes'));
    expect(android, contains('"avatarBytesBase64"'));
    expect(ios, contains('loadPhoto(for: .small)'));
    expect(ios, contains('payload["avatarBytesBase64"]'));
  });

  test('duel fee copy describes entry fee and winner pot separately', () {
    final source = File(
      'lib/features/duel/matchmaking_screen.dart',
    ).readAsStringSync();

    expect(source, contains('coin_required_body_dynamic'));
    expect(source, contains('winnerPotForDifficulty'));
    expect(source, isNot(contains(r"'$fee → $pot'")));
  });

  test('outcome header uses dedicated victory and defeat trophies', () {
    final source = File('lib/widgets/ux_feedback.dart').readAsStringSync();

    expect(source, contains('DuelAsset.resultVictoryTrophyPro'));
    expect(source, contains('DuelAsset.resultDefeatTrophyPro'));
  });

  test(
    'leaderboards use the competitive backend and retain optional native ELO entry',
    () {
      final source = File(
        'lib/features/duel/leaderboards_screen.dart',
      ).readAsStringSync();

      expect(source, contains('CompetitiveLeaderboardApi.instance'));
      expect(source, contains('_leaderboards.load('));
      expect(source, contains('SudokuVariant.classic9'));
      expect(source, contains('SudokuVariant.classic16'));
      expect(source, contains("_LeaderboardAudience.friends => 'friends'"));
      expect(source, contains("_LeaderboardAudience.aroundMe => 'around_me'"));
      expect(source, contains('PlatformLeaderboardService.instance'));
      expect(source, contains('_platformLeaderboards.show(_selectedScope)'));
    },
  );
}
