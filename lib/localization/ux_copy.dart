import 'package:flutter/material.dart';

import 'app_strings.dart';

class UxCopy {
  const UxCopy._();

  static String pause(BuildContext context) => context.tr('pause_game');

  static String pausedTitle(BuildContext context) => context.tr('game_paused');

  static String pausedBody(BuildContext context) => context.tr('pause_body');

  static String restartTitle(BuildContext context) =>
      context.tr('restart_puzzle_title');

  static String restartBody(BuildContext context) =>
      context.tr('restart_puzzle_body');

  static String fantasyTitle(BuildContext context) =>
      context.tr('fantasy_mode_title');

  static String fantasySubtitle(BuildContext context) =>
      'A long 16×16 board with symbols 1–9 and A–G.';

  static String fantasyBadge(BuildContext context) =>
      context.tr('offline_special_mode');

  static String genericError(BuildContext context) => 'Try again in a moment.';

  static String connectionError(BuildContext context) =>
      'Check your connection and try again.';

  static String accountError(BuildContext context) =>
      'Player account unavailable. Try again.';

  static String serverBusy(BuildContext context) =>
      'Service busy. Try again shortly.';

  static String emptyProfile(BuildContext context) => 'Profile not ready yet.';

  static String connectedPlatform(BuildContext context) => 'Platform connected';

  static String platformNotConnected(BuildContext context) =>
      'Platform not connected';

  static String overview(BuildContext context) => 'Overview';

  static String performance(BuildContext context) => 'Performance';

  static String accountAndSocial(BuildContext context) => 'Account & social';

  static String totalMatches(BuildContext context) => 'Matches';

  static String losses(BuildContext context) => 'Losses';

  static String draws(BuildContext context) => 'Draws';

  static String countryRank(BuildContext context) => 'Country rank';

  static String achievements(BuildContext context) => 'Achievements';

  static String loading(BuildContext context) => 'Loading...';

  static String noData(BuildContext context) => 'No data yet.';
}
