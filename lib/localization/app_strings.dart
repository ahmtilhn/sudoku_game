import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/sudoku.dart';

class AppStrings {
  AppStrings._(this._values);

  factory AppStrings.forTesting() =>
      AppStrings._(Map<String, String>.from(english));

  static const MethodChannel _channel = MethodChannel(
    'com.devovia.sudoku/localization',
  );

  static const String _catalogAsset =
      'assets/localization/Localizable.xcstrings';

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('pt'),
    Locale('it'),
    Locale('nl'),
    Locale('pl'),
    Locale('ru'),
    Locale('uk'),
    Locale('ar'),
    Locale('hi'),
    Locale('id'),
    Locale('ja'),
    Locale('ko'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('th'),
    Locale('vi'),
    Locale('bn'),
    Locale('ur'),
  ];

  static const Map<String, String> english = <String, String>{
    'app_name': 'Sudoku Duel',
    'home': 'Home',
    'play': 'Play',
    'compete': 'Compete',
    'profile': 'Profile',
    'settings': 'Settings',
    'career': 'Career',
    'career_subtitle': 'Progress from beginner to expert',
    'career_random_subtitle': 'Choose a difficulty and get a new puzzle',
    'career_random_intro':
        'Choose a difficulty. A fresh, unique Sudoku will be generated for every game.',
    'three_mistake_rule': 'Career rule: the round ends after 3 wrong moves.',
    'coins_count': '%1d coins',
    'random_clue_count': 'About %1d starting clues',
    'local_duel': 'Local Duel',
    'local_duel_subtitle': 'Take 10-second turns on the same device',
    'online_duel': 'Online Duel',
    'online_duel_subtitle': 'Choose a difficulty and match with the same queue',
    'choose_duel_difficulty': 'Choose your duel difficulty',
    'same_difficulty_match':
        'You will only be matched with players who selected the same difficulty.',
    'difficulty_queue': '%1s difficulty queue',
    'searching_opponent': 'Searching for an opponent…',
    'queue_key': 'Queue: %1s',
    'matchmaking_backend_pending':
        'The online connection will use this queue when the matchmaking backend is enabled.',
    'waiting_for_ranked_opponent':
        'You are in the ranked queue. The app checks for a match every few seconds.',
    'cancel_search': 'Cancel search',
    'find_opponent': 'Find opponent',
    'local_practice': 'Play local practice',
    'friend_requests': 'Friend requests',
    'friends_challenges': 'Friends & challenges',
    'quick_modes': 'Quick modes',
    'quick_duel': 'Quick Duel',
    'quick_duel_body': 'Find a ranked opponent at your selected difficulty.',
    'ranked': 'Ranked',
    'practice': 'Practice',
    'dismiss': 'Dismiss',
    'coin_required_title': '100 Coin required',
    'coin_required_body':
        'Each player contributes 100 Coin. The winner receives the 200 Coin pot.',
    'claim_daily_coin': 'Claim +%1d daily Coin',
    'watch_ad_for_coin': 'Watch ad for +%1d Coin',
    'matchmaking_unexpected_response':
        'The matchmaking server returned an unexpected response.',
    'matchmaking_start_failed':
        'Unable to start opponent search. Please try again.',
    'connection_interrupted_retrying':
        'The connection was interrupted. Retrying...',
    'leaderboards': 'Leaderboards',
    'global_elo': 'Global ELO',
    'friends': 'Friends',
    'country': 'Country',
    'current_season': 'Current season',
    'daily_tournament': 'Daily tournament',
    'weekend_tournament': 'Weekend tournament',
    'countries': 'Countries',
    'global': 'Global',
    'leaderboard_empty': 'No leaderboard entries yet.',
    'leaderboard_row': '%1d games · %2d%% win rate',
    'refresh': 'Refresh',
    'ready': 'Ready',
    'i_am_ready': 'I am ready',
    'stay': 'Stay',
    'forfeit_and_leave': 'Forfeit and leave',
    'online_forfeit_title': 'Forfeit match?',
    'online_forfeit_body':
        'Leaving an active online duel forfeits the match to your opponent.',
    'online_connection_failed': 'Online duel connection failed: %1s',
    'online_waiting_snapshot': 'Waiting for the server snapshot…',
    'connected': 'Connected',
    'reconnecting': 'Reconnecting',
    'your_turn': 'Your turn',
    'opponents_turn': "Opponent's turn",
    'online_turn_number': 'Turn %1d',
    'you': 'You',
    'turn_timer_seconds': '%1d s',
    'match_timer_seconds': '%1d s',
    'match_header_semantics': 'Online duel match header',
    'player_avatar_semantics': '%1s player avatar',
    'winner_avatar_semantics': '%1s winner avatar',
    'winner_name': 'Winner: %1s',
    'elo_value': 'ELO %1d',
    'turn_badge': 'Turn',
    'match_type': 'Match',
    'online_turns_label': 'Turns',
    'correct_moves': 'Correct moves',
    'timeouts': 'Timeouts',
    'not_available_short': 'N/A',
    'current_elo': 'Current ELO',
    'rank': 'Rank',
    'season_peak': 'Season peak',
    'country_not_set': 'No country',
    'wins_losses_draws': 'W/L/D',
    'win_rate': 'Win rate',
    'win_streak': 'Win streak',
    'tournament_entries': 'Tournament entries',
    'tournament_podiums': 'Tournament podiums',
    'country_contributions': 'Country contributions',
    'achievement_showcase': 'Achievement showcase',
    'achievement_showcase_empty': 'Choose up to three unlocked achievements.',
    'get_ready': 'Get ready',
    'connecting_players': 'Connecting players',
    'move_time_seconds': 'Move time: %1d s',
    'automatic_start_seconds': 'Automatic start: %1d s',
    'opponent_connecting': 'Opponent is connecting',
    'opponent_opening_game': 'Opponent is opening the game',
    'opponent_ready': 'Opponent is ready',
    'sending_move': 'Sending move…',
    'select_empty_cell_enter_number': 'Select an empty cell and enter a number',
    'waiting_opponent_move': 'Waiting for the opponent’s move',
    'you_won': 'You won!',
    'you_lost': 'You lost',
    'online_final_score': 'Final score: %1d — %2d',
    'final_score_label': 'Final score',
    'entry_fee': 'Entry fee',
    'winner_pot': 'Winner pot',
    'refund': 'Refund',
    'match_result': 'Match result',
    'current_balance': 'Current balance',
    'rating': 'Rating',
    'finish_reason': 'Finish reason',
    'coin_amount': '%1d Coin',
    'vs_opponent': 'vs %1s',
    'waiting_for_player_seconds': 'Waiting for %1s · %2d s',
    'wants_rematch_seconds': '%1s wants a rematch · %2d s',
    'decline': 'Decline',
    'accept': 'Accept',
    'challenge_again': 'Challenge again',
    'find_new_match': 'Find new match',
    'add_friend': 'Add friend',
    'open_coin_store': 'Open Coin Store',
    'not_enough_coins_online':
        'You need at least %1d Coin to play another online match.',
    'rematch_invitation_sent': 'Rematch invitation sent.',
    'rematch_declined': 'Rematch declined.',
    'rematch_invitation_title': 'Rematch invitation',
    'wants_to_play_again': '%1s wants to play again.',
    'challenge_declined': 'Challenge declined.',
    'challenge_timed_out': 'Challenge timed out.',
    'friend_request_sent': 'Friend request sent.',
    'player_not_enough_coin': 'A player no longer has enough Coin.',
    'rating_delta': 'Global rating: %1d → %2d (%3d)',
    'daily_sudoku': 'Daily Sudoku',
    'daily_subtitle': 'One fresh puzzle every day',
    'how_to_play': 'How to play',
    'tutorial_repeat': 'Open the tutorial again',
    'tutorial_new': 'Learn in minutes with a 4×4 board',
    'welcome_returning_title': 'Ready for a Sudoku?',
    'welcome_new_title': "You don't need to know Sudoku.",
    'welcome_returning_body':
        'Continue your career or challenge another player.',
    'welcome_new_body':
        'Learn the rules with a quick tutorial, then start your career.',
    'career_intro': 'Start with the easiest puzzles and progress step by step.',
    'difficulty_beginner': 'Beginner',
    'difficulty_easy': 'Easy',
    'difficulty_medium': 'Medium',
    'difficulty_hard': 'Hard',
    'difficulty_expert': 'Expert',
    'complete_previous_level': 'Complete the previous level',
    'new_level': 'New level',
    'best_time': 'Best: %1s',
    'level_title': '%1s %2d',
    'daily_puzzle_title': 'Daily Sudoku',
    'duel_puzzle_title': 'Duel',
    'mini_sudoku_title': 'Mini Sudoku',
    'congratulations': 'Congratulations!',
    'time': 'Time',
    'mistakes': 'Mistakes',
    'hints': 'Hints',
    'continue_action': 'Continue',
    'mistakes_count': 'Mistakes: %1d',
    'mistakes_limit_count': 'Mistakes: %1d/%2d',
    'hints_count': 'Hints: %1d',
    'round_lost': 'Round lost',
    'mistake_limit_reached':
        'You made %1d wrong moves. Choose how you want to continue.',
    'continue_with_coins': 'Continue for %1d coins',
    'watch_rewarded_ad': 'Watch rewarded ad',
    'restart_puzzle': 'Restart from the beginning',
    'not_enough_coins': 'You do not have enough coins.',
    'rewarded_ad_unavailable': 'The rewarded ad is not available right now.',
    'rewarded_ad_prototype_body':
        'The rewarded ad provider will be connected in the monetization phase. Continue now to test the recovery flow.',
    'time_up_turn_passed': 'Time is up. The turn passed to the other player.',
    'draw': 'Draw!',
    'player_won': 'Player %1d won!',
    'turns_played': '%1d turns played.',
    'main_menu': 'Main menu',
    'turn': 'Turn %1d',
    'seconds': '%1d seconds',
    'player_instruction': 'Player %1d: Select a cell and make one move.',
    'player': 'Player %1d',
    'today_puzzle_completed': "Today's puzzle is complete!",
    'tutorial_title': 'How to play Sudoku',
    'rule_rows_title': 'Complete each row',
    'rule_rows_description': 'Each number can appear only once in every row.',
    'rule_columns_title': 'Check each column',
    'rule_columns_description':
        'The same number cannot appear twice in a column.',
    'rule_boxes_title': 'Remember the boxes',
    'rule_boxes_description':
        'Each bold box must also contain every number once.',
    'tutorial_ready': 'Ready? Try a 4×4 mini Sudoku.',
    'tutorial_completed': 'You understand Sudoku!',
    'start_mini_tutorial': 'Start mini tutorial',
    'appearance': 'Appearance',
    'system': 'System',
    'light': 'Light',
    'dark': 'Dark',
    'high_contrast': 'High contrast',
    'high_contrast_subtitle': 'Makes the board and text easier to distinguish.',
    'notifications': 'Notifications',
    'daily_sudoku_challenges': 'Daily Sudoku challenges',
    'daily_sudoku_challenges_subtitle':
        'Three optional reminders each day at 09:00, 15:00, and 20:30. You can turn them off at any time.',
    'daily_reminder_permission_denied':
        'Notification permission was not granted. Daily reminders remain off.',
    'online_challenge_notifications': 'Online challenge notifications',
    'online_challenge_notifications_subtitle':
        'Shows friend and challenge invitations on this device. You can turn this off at any time.',
    'online_challenge_notifications_unavailable':
        'Challenge notifications require Firebase and the social backend to be configured.',
    'challenge_notification_permission_denied':
        'Notification permission was not granted. Online challenge notifications remain off.',
    'player_account': 'Player account',
    'player_account_protected': 'Player account protected',
    'protect_player_account': 'Protect player account',
    'protect_your_player_account': 'Protect your player account',
    'account_protection_banner_body':
        'Link an email before buying Coins so your wallet, Friend ID and rating can be recovered after reinstall or device change.',
    'protect': 'Protect',
    'coin_store': 'Coin Store',
    'coin_history': 'Coin history',
    'protect_account_before_buying': 'Protect your account before buying',
    'paid_coins_protection_body':
        'Paid Coins must be linked to a recoverable email account. Your current guest wallet and Friend ID are preserved when you protect this account.',
    'create_player_profile': 'Create your player profile',
    'create_player_profile_body':
        'Your display name is shown in matches. Your unique username can be searched, while your permanent Friend ID never changes.',
    'use_platform_name': 'Use your Google Play Games or Game Center name',
    'use_custom_profile': 'Use a custom profile',
    'display_name': 'Display name',
    'unique_username': 'Unique username',
    'username_helper': '3–20 lowercase letters, numbers or underscore',
    'friend_id_value': 'Friend ID: %1s',
    'player_profile': 'Player profile',
    'shown_to_other_players': 'Shown to other players',
    'save': 'Save',
    'friend_id_copied': 'Friend ID copied.',
    'online_account_unavailable': 'Online account unavailable',
    'try_again_when_connected': 'Try again when connected.',
    'retry': 'Retry',
    'edit_player_profile': 'Edit player profile',
    'friend_id': 'Friend ID',
    'copy_friend_id': 'Copy Friend ID',
    'discoverable_by_players': 'Discoverable by other players',
    'discoverable_by_players_body':
        'Allow username, display-name and exact Friend ID search. Existing friends remain connected when disabled.',
    'server_wallet_history': 'Server wallet and purchase history',
    'rematch_could_not_start': 'Rematch could not be started.',
    'rematch_invitation_load_failed':
        'The rematch invitation could not be loaded.',
    'rematch_requires_coin': 'A new match requires %1d Coin from each player.',
    'privacy': 'Privacy',
    'analytics_sharing': 'Analytics sharing',
    'analytics_sharing_subtitle':
        'Allows anonymous usage analytics to help improve Sudoku Duel.',
    'crash_reports_sharing': 'Crash reports sharing',
    'crash_reports_sharing_subtitle':
        'Sends crash diagnostics when something fails.',
    'ad_privacy': 'Ad privacy',
    'ad_privacy_choices': 'Ad privacy choices',
    'ad_privacy_choices_subtitle':
        'Review or change the privacy choices used for advertising.',
    'data': 'Data',
    'clear_career_progress': 'Clear career progress',
    'completed_levels': '%1d completed levels',
    'clear_progress_title': 'Clear progress?',
    'clear_progress_body':
        'Completed career levels and records will be removed.',
    'cancel': 'Cancel',
    'clear': 'Clear',
    'erase': 'Erase',
    'notes_on': 'Notes on',
    'notes': 'Notes',
    'undo': 'Undo',
    'hint': 'Hint',
    'board_label': '%1d by %1d Sudoku board',
    'cell_label': 'Row %1d, column %2d, %3s',
    'empty': 'Empty',
  };

  final Map<String, String> _values;

  static Future<AppStrings> load() async {
    final values = Map<String, String>.from(english);
    await _loadStringCatalog(values);
    try {
      final response = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getStrings',
        <String, Object>{'keys': english.keys.toList(growable: false)},
      );
      if (response != null) {
        for (final entry in response.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is String &&
              value is String &&
              value.isNotEmpty &&
              value != key) {
            values[key] = value;
          }
        }
      }
    } on MissingPluginException {
      // Unit tests and unsupported platforms use the catalog or English fallback.
    } on PlatformException {
      // A platform localization failure must never block app startup.
    }
    return AppStrings._(values);
  }

  static Future<void> _loadStringCatalog(Map<String, String> values) async {
    try {
      final source = await rootBundle.loadString(_catalogAsset);
      final catalog = jsonDecode(source) as Map<String, dynamic>;
      final catalogStrings = catalog['strings'];
      if (catalogStrings is! Map) return;

      final locale = PlatformDispatcher.instance.locale;
      final candidates = <String>[
        locale.toLanguageTag(),
        if (locale.scriptCode != null)
          '${locale.languageCode}-${locale.scriptCode}',
        locale.languageCode,
        'en',
      ];

      for (final entry in catalogStrings.entries) {
        final key = entry.key.toString();
        final definition = entry.value;
        if (definition is! Map) continue;
        final localizations = definition['localizations'];
        if (localizations is! Map) continue;
        for (final candidate in candidates) {
          final localization = localizations[candidate];
          if (localization is! Map) continue;
          final stringUnit = localization['stringUnit'];
          if (stringUnit is! Map) continue;
          final value = stringUnit['value'];
          if (value is String && value.isNotEmpty) {
            values[key] = value;
            break;
          }
        }
      }
    } on FlutterError {
      // The catalog is optional on platforms that use native resources.
    } on FormatException {
      // Keep the English fallback if a catalog is temporarily malformed.
    }
  }

  String text(String key, [List<Object> arguments = const <Object>[]]) {
    var value = _values[key] ?? english[key] ?? key;
    for (var index = 0; index < arguments.length; index++) {
      final position = index + 1;
      final replacement = arguments[index].toString();
      value = value
          .replaceAll('%$position\$s', replacement)
          .replaceAll('%$position\$d', replacement)
          .replaceAll('%${position}s', replacement)
          .replaceAll('%${position}d', replacement);
    }
    return value;
  }

  String difficultyLabel(SudokuDifficulty difficulty) => switch (difficulty) {
    SudokuDifficulty.beginner => text('difficulty_beginner'),
    SudokuDifficulty.easy => text('difficulty_easy'),
    SudokuDifficulty.medium => text('difficulty_medium'),
    SudokuDifficulty.hard => text('difficulty_hard'),
    SudokuDifficulty.expert => text('difficulty_expert'),
  };

  String puzzleTitle(SudokuPuzzle puzzle) {
    if (puzzle.id == 'tutorial-4x4') {
      return text('mini_sudoku_title');
    }
    if (puzzle.id.startsWith('daily-')) {
      return text('daily_puzzle_title');
    }
    if (puzzle.id.startsWith('duel-')) {
      return text('duel_puzzle_title');
    }
    if (puzzle.id.startsWith('career-random-') ||
        puzzle.id.startsWith('sample-')) {
      return difficultyLabel(puzzle.difficulty);
    }
    final level = int.tryParse(puzzle.id.split('-').last);
    if (level != null) {
      return text('level_title', <Object>[
        difficultyLabel(puzzle.difficulty),
        level,
      ]);
    }
    return puzzle.title;
  }
}

class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  final AppStrings strings;

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    assert(scope != null, 'AppStringsScope is missing above this context.');
    return scope!.strings;
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      oldWidget.strings != strings;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStringsScope.of(this);

  String tr(String key, [List<Object> arguments = const <Object>[]]) =>
      strings.text(key, arguments);
}
