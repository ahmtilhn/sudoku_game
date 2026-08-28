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
      context.tr('fantasy_subtitle');

  static String fantasyBadge(BuildContext context) =>
      context.tr('offline_special_mode');

  static String genericError(BuildContext context) =>
      context.tr('generic_try_again_moment');

  static String connectionError(BuildContext context) =>
      context.tr('connection_try_again');

  static String accountError(BuildContext context) =>
      context.tr('player_account_try_again');

  static String serverBusy(BuildContext context) =>
      context.tr('service_busy_try_again');

  static String emptyProfile(BuildContext context) =>
      context.tr('profile_not_ready');

  static String connectedPlatform(BuildContext context) =>
      context.tr('platform_connected');

  static String platformNotConnected(BuildContext context) =>
      context.tr('platform_not_connected');

  static String overview(BuildContext context) => context.tr('overview');

  static String performance(BuildContext context) => context.tr('performance');

  static String accountAndSocial(BuildContext context) =>
      context.tr('account_social');

  static String totalMatches(BuildContext context) => context.tr('matches');

  static String losses(BuildContext context) => context.tr('losses');

  static String draws(BuildContext context) => context.tr('draws');

  static String countryRank(BuildContext context) => context.tr('country_rank');

  static String achievements(BuildContext context) =>
      context.tr('achievements');

  static String loading(BuildContext context) => context.tr('loading');

  static String noData(BuildContext context) => context.tr('no_data_yet');
}
