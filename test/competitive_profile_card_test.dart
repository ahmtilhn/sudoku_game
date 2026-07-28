import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/features/social/competitive_profile_card.dart';
import 'package:sudoku_game/localization/app_strings.dart';
import 'package:sudoku_game/services/social_api_client.dart';

void main() {
  testWidgets(
    'competitive profile renders without Firebase or platform account',
    (tester) async {
      await _pumpProfile(tester, _profile());

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('@ada · FRIEND1'), findsOneWidget);
      expect(find.textContaining('No country'), findsOneWidget);
      expect(find.textContaining('1200'), findsWidgets);
    },
  );

  testWidgets('competitive profile handles private profile and showcase', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      _profile(
        privateProfile: true,
        country: 'TR',
        showcase: const <SocialAchievement>[
          SocialAchievement(
            id: 'first_win',
            category: 'ranked',
            title: 'First Duel Win',
            tier: 'bronze',
            unlocked: true,
          ),
        ],
      ),
    );

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.textContaining('TR'), findsOneWidget);
    expect(find.text('First Duel Win'), findsOneWidget);
  });
}

Future<void> _pumpProfile(
  WidgetTester tester,
  CompetitiveProfile profile,
) async {
  await tester.pumpWidget(
    AppStringsScope(
      strings: AppStrings.forTesting(),
      child: MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.ltr,
            child: CompetitiveProfileCard(profile: profile),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

CompetitiveProfile _profile({
  bool privateProfile = false,
  String? country,
  List<SocialAchievement> showcase = const <SocialAchievement>[],
}) {
  return CompetitiveProfile(
    publicId: 'FRIEND1',
    username: 'ada',
    displayName: 'Ada',
    avatarKey: 'default',
    country: country,
    currentElo: 1200,
    rank: 12,
    rankName: 'Gold',
    seasonPeak: 1250,
    wins: 8,
    losses: 3,
    draws: 1,
    winRate: 8 / 12,
    winStreak: 4,
    tournamentEntries: 2,
    tournamentPodiums: 1,
    countryContributions: 30,
    achievementCount: showcase.length,
    achievementShowcase: showcase,
    privateProfile: privateProfile,
  );
}
