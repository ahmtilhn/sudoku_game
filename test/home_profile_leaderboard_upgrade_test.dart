import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home uses premium scene artwork and exposes distinct profile/rank paths', () {
    final source = File(
      'lib/features/home/professional_home_screen.dart',
    ).readAsStringSync();

    for (final asset in <String>[
      'DuelAsset.homePlayScene',
      'DuelAsset.homeDuelScene',
      'DuelAsset.homeCareerScene',
      'DuelAsset.homeFriendsScene',
      'DuelAsset.homeStoreScene',
      'DuelAsset.resultVictoryTrophyPro',
      'DuelAsset.dailyRewardPro',
      'DuelAsset.coin',
      'DuelAsset.leaderboardCrownPro',
    ]) {
      expect(source, contains(asset));
    }
    expect(source, contains('LeaderboardsScreen'));
    expect(source, contains('RankedProgressScreen'));
    expect(source, contains("title: rank?.rankName ?? 'Ranked Progress'"));
    expect(source, contains('progress: rank?.progress'));
    expect(source, contains('onTap: _identityBusy ? null : _openRankedProgress'));
    expect(source, isNot(contains('DuelAsset.homeProfileScene')));
    expect(source, contains('localAvatarBytes: platformPlayer?.avatarBytes'));
    expect(
      source,
      contains('constraints: const BoxConstraints(maxWidth: 760)'),
    );
  });

  test('ranked progress screen owns RP detail instead of another home profile shortcut', () {
    final source = File(
      'lib/features/duel/ranked_progress_screen.dart',
    ).readAsStringSync();

    expect(source, contains('RankIdentitySummaryCard'));
    expect(source, contains('RankIdentityService.instance.refresh()'));
    expect(source, contains('ProfileCustomizationScreen'));
    expect(source, contains('LeaderboardsScreen'));
    expect(source, contains("title: 'Ranked Progress'"));
  });

  test('profile hub exposes RP identity customization and leaderboard entry', () {
    final source = File(
      'lib/features/social/profile_hub_screen.dart',
    ).readAsStringSync();
    final summary = File(
      'lib/features/social/rank_identity_summary_card.dart',
    ).readAsStringSync();

    expect(source, contains('RankIdentitySummaryCard'));
    expect(source, contains('ProfileCustomizationScreen'));
    expect(source, contains('_ProfileActionGrid'));
    expect(source, contains('_ProfileActionCard'));
    expect(source, contains('_selectedTab'));
    expect(source, contains('DuelAsset.leaderboardCrownPro'));
    expect(source, contains('LeaderboardsScreen'));
    expect(source, contains('rankPoints'));
    expect(source, contains('_selectedTab = _ProfileTab.leaderboards'));
    expect(source, isNot(contains('CompetitiveProfileCard')));
    expect(source, isNot(contains('currentElo')));
    expect(source, isNot(contains('WalletHistoryScreen')));
    expect(source, isNot(contains('SocialHubScreen')));

    expect(summary, contains('profile.rankPoints'));
    expect(summary, contains('profile.rankName'));
    expect(summary, contains('profile.avatarKey'));
    expect(summary, isNot(contains('currentElo')));
  });

  test('store and page chrome use transparent glass styling', () {
    final theme = File('lib/core/app_theme.dart').readAsStringSync();
    final store = File(
      'lib/features/economy/coin_store_screen.dart',
    ).readAsStringSync();

    expect(theme, contains('backgroundColor: Colors.transparent'));
    expect(theme, contains('surfaceTintColor: Colors.transparent'));
    expect(store, contains('class _StorePanel'));
    expect(store, contains('Colors.white.withValues(alpha: .045)'));
    expect(store, isNot(contains('return Card(')));
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
    expect(dart, contains('effectiveDisplayName'));
    expect(dart, contains("rawAlias?.isNotEmpty == true"));
    expect(android, contains('avatarBytesBase64'));
    expect(android, contains('downloadAvatarBytes'));
    expect(android, contains('"avatarBytesBase64"'));
    expect(
      android,
      contains('"loadRecentPlayers" -> loadRecentPlayers(result)'),
    );
    expect(android, contains('"showFriends" -> showFriends(result)'));
    expect(ios, contains('loadPhoto(for: .small)'));
    expect(ios, contains('payload["avatarBytesBase64"]'));
    expect(ios, contains('case "leaderboardIds"'));
    expect(ios, contains('authentication_timeout'));
    expect(ios, contains('leaderboardsConfigured'));
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
    'in-app competitive ladder uses visible RP while native boards stay isolated',
    () {
      final source = File(
        'lib/features/duel/leaderboards_screen.dart',
      ).readAsStringSync();

      expect(source, contains('RankIdentityService.instance'));
      expect(source, contains('loadLeaderboard(limit: 100)'));
      expect(source, contains('rankPoints'));
      expect(source, contains("'Global RP leaderboard'"));
      expect(source, isNot(contains("'Rank progression'")));
      expect(source, isNot(contains('_RankRoadmap')));
      expect(source, isNot(contains('rankTierCatalog')));
      expect(source, isNot(contains('CompetitiveLeaderboardApi.instance')));
      expect(source, isNot(contains('PlatformLeaderboardService.instance')));
      expect(source, isNot(contains('Sudoku Duel ELO')));
      expect(source, isNot(contains('entry.copyWith(rank:')));

      final service = File(
        'lib/services/rank_identity_service.dart',
      ).readAsStringSync();
      expect(service, contains("'/v1/competitive/rank-leaderboard?limit="));
      expect(service, contains('FirebaseSessionService.ensureAnonymousSession()'));

      // Native platform leaderboards remain a separate compatibility surface;
      // they do not define the in-app visible rank.
      final platform = File(
        'lib/features/social/platform_services_screen.dart',
      ).readAsStringSync();
      expect(platform, contains('PlatformLeaderboardService.instance'));
    },
  );
}
