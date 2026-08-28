import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
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
    'samurai_sudoku': 'Samurai Sudoku',
    'duel_variant_classic': 'Classic Sudoku',
    'choose_duel_variant': 'Choose game type',
    'same_variant_match': 'You will only be matched with the same game type.',
    'samurai_subtitle': 'Five overlapping 9×9 boards in one challenge',
    'samurai_choose_difficulty': 'Choose Samurai difficulty',
    'samurai_zoom_hint':
        'Pinch to zoom and drag to move across the five linked boards.',
    'samurai_pause_body':
        'Your five linked boards are paused. Continue when ready.',
    'samurai_completed_title': 'Samurai completed!',
    'samurai_completed_body': 'You solved all five linked Sudoku boards.',
    'three_mistake_rule': 'Career rule: the round ends after 3 wrong moves.',
    'coins_count': '%1d coins',
    'random_clue_count': 'About %1d starting clues',
    'local_duel': 'Local Duel',
    'local_duel_subtitle': 'Take 10-second turns on the same device',
    'online_duel': 'Online Duel',
    'online_duel_subtitle': 'Choose a difficulty and match with the same queue',
    'online_duel_fee_summary': 'Online entry starts at %1d Coin',
    'choose_duel_difficulty': 'Choose your duel difficulty',
    'same_difficulty_match':
        'You will only be matched with players who selected the same difficulty.',
    'difficulty_queue': '%1s difficulty queue',
    'searching_opponent': 'Searching for an opponent…',
    'finding_opponent_title': 'Finding Opponent',
    'searching_similar_opponents': 'Searching for opponents near your level...',
    'searching_opponent_short': 'Searching',
    'ready_question': 'Are You Ready?',
    'ready_when_opponent_ready': 'The game starts when both players are ready.',
    'waiting_opponent_ready': 'Waiting for your opponent...',
    'match_ready_prompt': 'Tap ready when you are set.',
    'you_ready_waiting_opponent': 'You are ready. Waiting for your opponent.',
    'opponent_ready_waiting_you': 'Opponent is ready. Waiting for you.',
    'everyone_ready_starting': 'Everyone is ready. Starting the game...',
    'elo_hint': 'Your ELO rises when you win and falls when you lose.',
    'world': 'World',
    'elo_unknown': 'ELO',
    'opponent': 'Opponent',
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
    'home_progress_summary': '%1d career levels · %2d Coin',
    'home_rating_label': 'ELO',
    'home_daily_reward_title': 'Daily bonus',
    'home_daily_reward_body': 'Claim today\'s reward from the gift button.',
    'daily_reward_day_title': 'Day %1d reward',
    'coin_reward_value': '+%1d Coins',
    'hint_refill_reward_value': '+1 Hint Refill',
    'daily_reward_doubled': 'Daily reward doubled.',
    'daily_reward_track_body':
        'Come back tomorrow to continue your 30-day track.',
    'hint_refill_reward_body':
        'A Hint Refill restores an empty hint meter to full.',
    'loading': 'Loading...',
    'watch_ad_reward_value': 'Watch ad · +%1d',
    'collect': 'Collect',
    'home_play_online_cta': 'Play',
    'home_online_badge': 'Same difficulty matchmaking',
    'home_career_card_body': 'Keep building your Sudoku fundamentals.',
    'home_wallet_label': 'Wallet',
    'home_progress_label': 'Progress',
    'ranked': 'Ranked',
    'practice': 'Practice',
    'dismiss': 'Dismiss',
    'coin_required_title': '100 Coin required',
    'coin_required_body':
        'Each player contributes 100 Coin. The winner receives the 200 Coin pot.',
    'coin_required_title_dynamic': '%1d Coin required',
    'coin_required_body_dynamic':
        'Each player contributes %1d Coin. The winner receives the %2d Coin pot.',
    'claim_daily_coin': 'Claim +%1d daily Coin',
    'watch_ad_for_coin': 'Watch ad for +%1d Coin',
    'matchmaking_unexpected_response':
        'The matchmaking server returned an unexpected response.',
    'matchmaking_start_failed':
        'Unable to start opponent search. Please try again.',
    'connection_interrupted_retrying':
        'The connection was interrupted. Retrying...',
    'leaderboards': 'Leaderboards',
    'ranked_ladder': 'Ranked ladder',
    'ranked_progress_title': 'Ranked Progress',
    'rank_progression': 'Rank progression',
    'global_rp_leaderboard': 'Global RP leaderboard',
    'current_elo_summary': '%1d ELO · %2d games · %3dW %4dL',
    'native_leaderboard_short': 'Native',
    'global_elo': 'Global ELO',
    'friends': 'Friends',
    'country': 'Country',
    'current_season': 'Current season',
    'daily_tournament': 'Daily tournament',
    'weekend_tournament': 'Weekend tournament',
    'countries': 'Countries',
    'global': 'Global',
    'leaderboard_empty': 'No leaderboard entries yet.',
    'leaderboard_empty_hint':
        'Sudoku Duel ELO fills after ranked online matches are completed.',
    'leaderboard_row': '%1d games · %2d% win rate',
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
    'last_move': 'Last move',
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
    'platform_leaderboards_body': 'Global ELO and difficulty boards',
    'platform_global_rank_body': 'Your main platform ranking',
    'platform_difficulty_rank_body': 'Ranking for this difficulty',
    'platform_achievements_body': 'Open achievements and progress',
    'classic_9x9': '9x9',
    'classic_16x16': '16x16',
    'classic_variants_short': '9x9 · 16x16',
    'top_rank': 'Top rank',
    'your_rank': 'Your rank',
    'no_score': 'No score',
    'no_elo': 'No ELO',
    'board': 'Board',
    'entries_shown': '%1d shown',
    'account': 'Account',
    'private_label': 'Private',
    'record': 'Record',
    'games_count': '%1d games',
    'wins': 'Wins',
    'losses': 'Losses',
    'games': 'Games',
    'ok': 'OK',
    'close': 'Close',
    'coin': 'Coin',
    'sudoku': 'Sudoku',
    'tier_master': 'Master',
    'tier_diamond': 'Diamond',
    'tier_platinum': 'Platinum',
    'tier_gold': 'Gold',
    'tier_silver': 'Silver',
    'tier_bronze': 'Bronze',
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
    'result_win_subtitle': 'Great play!',
    'result_loss_subtitle': 'Good effort. Try the rematch.',
    'result_draw_subtitle': 'Even match.',
    'versus_short': 'VS',
    'result_elo_change': 'ELO change',
    'rating_value': '%1d ELO',
    'coin_result': 'Coin result',
    'online_final_score': 'Final score: %1d — %2d',
    'final_score_label': 'Final score',
    'entry_fee': 'Entry fee',
    'winner_pot': 'Winner pot',
    'duel_fee_summary': '%1d entry · %2d winner pot',
    'balance_loading': 'Balance: ...',
    'balance_coin': 'Balance: %1d Coin',
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
    'rematch_waiting_room': 'Starting the rematch...',
    'rematch_declined': 'Rematch declined.',
    'rematch_invitation_title': 'Rematch invitation',
    'wants_to_play_again': '%1s wants to play again.',
    'challenge_declined': 'Challenge declined.',
    'challenge_sent_to': 'Challenge sent to %1s.',
    'challenge_player': 'Challenge %1s',
    'challenge_expires_at': '%1s challenge · expires %2s',
    'challenge_timed_out': 'Challenge timed out.',
    'friend_request_sent': 'Friend request sent.',
    'friend_request_sent_to': 'Friend request sent to %1s.',
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
    'pause': 'Pause',
    'pause_game': 'Pause game',
    'game_paused': 'Game paused',
    'pause_body': 'Paused. Continue when ready.',
    'restart_puzzle_title': 'Restart puzzle?',
    'restart_puzzle_body': 'Moves and time will be cleared.',
    'fantasy_mode_title': 'Fantasy Mode · 16×16',
    'fantasy_level_title': '16x16 Level %1d',
    'offline_special_mode': 'Offline special mode',
    'milestone': 'Milestone',
    'stars': 'Stars',
    'track': 'Track',
    'chapter': 'Chapter',
    'next_level': 'Next level',
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
    'skip': 'Skip',
    'earn_career_ad_coin': 'Earn %1d Coin',
    'career_ad_reward_body':
        'Watch an optional rewarded ad after this completed puzzle.',
    'watch_and_earn_coin': 'Watch and earn +%1d Coin',
    'coin_added_wallet': '%1d Coin added to your wallet.',
    'turn': 'Turn %1d',
    'seconds': '%1d seconds',
    'seconds_short': 's',
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
    'daily_sudoku_challenges_channel':
        'Daily reminders to return for a fresh Sudoku challenge.',
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
    'delete_player_account': 'Delete player account',
    'delete_player_account_body':
        'Removes wallet, purchases, Friend ID, friends, rating and match history.',
    'sign_in_protected_account': 'Sign in to a protected account',
    'protect_current_guest': 'Protect the current guest',
    'sign_in_protected_account_body':
        'Use the same wallet, Friend ID and rating here.',
    'protect_current_guest_body':
        'Link email and password without changing this player.',
    'email_address': 'Email address',
    'password': 'Password',
    'password_min_chars': 'At least 8 characters',
    'show_password': 'Show password',
    'hide_password': 'Hide password',
    'confirm_password': 'Confirm password',
    'passwords_do_not_match': 'Passwords do not match.',
    'please_wait': 'Please wait...',
    'sign_in': 'Sign in',
    'protect_account': 'Protect account',
    'forgot_password': 'Forgot password?',
    'sign_in_switches_guest':
        'Signing in switches away from this guest. Wallets are not merged.',
    'account_protected': 'Account protected',
    'protected_account': 'Protected account',
    'email_verified': 'Email verified',
    'email_verification_required': 'Email verification required',
    'paid_coins_recoverable':
        'Paid Coin purchases can be recovered on another device.',
    'verify_email_before_buying': 'Verify email before buying Coins.',
    'resend_verification_email': 'Resend verification email',
    'verified_refresh': 'I verified it - refresh',
    'send_password_reset_email': 'Send password reset email',
    'sign_out_on_device': 'Sign out on this device',
    'protected_player_account_opened': 'Protected player account opened.',
    'account_protected_verify_email':
        'Account protected. Check your inbox to verify the email.',
    'verification_email_sent': 'Verification email sent.',
    'email_verified_notice': 'Email verified.',
    'account_refreshed': 'Account refreshed.',
    'password_reset_email_sent': 'Password reset email sent.',
    'sign_out_question': 'Sign out?',
    'sign_out_body':
        'The protected wallet stays on the account. This device will use a guest until you sign in again.',
    'sign_out': 'Sign out',
    'guest_player_created': 'Guest player created.',
    'delete_player_account_question': 'Delete player account permanently?',
    'delete_player_account_warning':
        'This cannot be undone. Wallet, purchases, friends, rating and match history will be removed. Finish active online matches first.',
    'type_delete': 'Type DELETE',
    'current_password': 'Current password',
    'delete_permanently': 'Delete permanently',
    'player_account_deleted': 'Player account and online data deleted.',
    'protect_current': 'Protect current',
    'recoverable_account': 'Recoverable account',
    'guest_account': 'Guest account',
    'email_account': 'an email account',
    'online_identity_linked': 'Online identity linked to %1s.',
    'guest_account_risk':
        'Deleting the app or changing devices can make this guest inaccessible. Protect it before buying Coins.',
    'coin_store': 'Coin Store',
    'your_balance': 'Your balance',
    'popular': 'Popular',
    'coin_pack_title': '%1s Coins',
    'coin_pack_body': 'Add Coins to your wallet',
    'daily_day_short': 'Day %1d',
    'claim_hint_refill': 'Claim Hint Refill',
    'use_hint_refill': 'Use refill · %1d left (+%2d hints)',
    'hint_refill_unavailable': 'Hint refill is not available right now.',
    'hint_refill_short': 'Refill',
    'daily_hint_refill_reward': 'Hint Refill added.',
    'no_ads_title': 'Remove ads',
    'no_ads_body': 'Hide rewarded ad offers on this player account.',
    'no_ads_owned': 'Ads are removed on this player account.',
    'restore_purchases': 'Restore purchases',
    'coin_history': 'Coin history',
    'coin_history_empty': 'No Coin activity yet.',
    'coin_history_balance_after': '%1s · Balance %2s',
    'ledger_starter_grant': 'Starter Coins',
    'ledger_match_entry': 'Online match entry',
    'ledger_match_payout': 'Match prize',
    'ledger_match_refund': 'Match refund',
    'ledger_daily_login': 'Daily login reward',
    'ledger_daily_rewarded_ad': 'Daily ad reward',
    'ledger_career_rewarded_ad': 'Career ad reward',
    'ledger_achievement_reward': 'Achievement reward',
    'ledger_career_continue': 'Career continue',
    'ledger_hint_purchase': 'Hint purchase',
    'ledger_store_purchase': 'Coin Store purchase',
    'ledger_purchase_refund': 'Purchase refund',
    'protect_account_before_buying': 'Protect your account before buying',
    'paid_coins_protection_body':
        'Paid Coins must be linked to a recoverable email account. Your current guest wallet and Friend ID are preserved when you protect this account.',
    'account_data': 'Account & data',
    'account_data_body':
        'Protect or recover the player account, sign out, and permanently delete the account and server data.',
    'service_diagnostics': 'Service diagnostics',
    'service_diagnostics_subtitle':
        'Check the installed build, Firebase session and social server.',
    'service_diagnostics_ready': 'Online services are reachable',
    'service_diagnostics_needs_attention':
        'One or more online checks need attention',
    'service_diagnostics_copied': 'Diagnostics copied.',
    'copy_diagnostics': 'Copy diagnostics',
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
    'friend_requests_setup_required':
        'Deploy the social backend and configure Firebase before using friend requests.',
    'service_message': 'Service message',
    'search_results': 'Search results',
    'sudoku_duel_friends': 'Sudoku Duel friends',
    'friends_empty_body':
        'Search a username and send a friend request to build your list.',
    'recent_opponents': 'Recent opponents',
    'recent_opponents_empty_body':
        'Players you finish an online match with will appear here.',
    'cross_platform_social_service': 'Cross-platform social service',
    'cross_platform_social_service_body':
        'Sudoku Duel usernames, friends, recent opponents, and challenges are connected through the shared backend.',
    'challenge_notifications_enabled': 'Challenge notifications enabled',
    'enable_challenge_notifications': 'Enable challenge notifications',
    'challenge_notifications_body':
        'Receive invitations and responses even while Sudoku Duel is closed.',
    'enable': 'Enable',
    'search_sudoku_duel_username': 'Search Sudoku Duel username',
    'enter_three_characters': 'Enter at least 3 characters.',
    'search': 'Search',
    'pending_challenges': 'Pending challenges',
    'no_pending_challenges': 'No pending challenges',
    'pending_challenges_empty_body':
        'New invitations will appear here and can also arrive by push notification.',
    'connect_platform_profile': 'Connect platform profile',
    'connect_platform_profile_body':
        'Use Play Games or Game Center for native friends, leaderboards, achievements, and player profiles.',
    'connected_player': 'Connected player',
    'leaderboard': 'Leaderboard',
    'achievements': 'Achievements',
    'friend_requests_empty': 'You have no pending friend requests.',
    'friend_request_accepted': '%1s is now your friend.',
    'friend_request_declined': 'Friend request declined.',
    'player_rating_summary': '@%1s · %2d rating',
    'player_rating_wins_summary': '@%1s · %2d rating · %3d/%4d wins',
    'challenge': 'Challenge',
    'platform_friends': 'Platform friends',
    'platform_friends_empty_title': 'No platform friends available',
    'platform_friends_empty_body':
        'Friend access may not be granted, or no matching Play Games/Game Center friends were returned.',
    'open_native_platform_profile': 'Open native platform profile',
    'online_account_unavailable': 'Online account unavailable',
    'try_again_when_connected': 'Try again when connected.',
    'try_again': 'Try again',
    'retry': 'Retry',
    'edit_player_profile': 'Edit player profile',
    'profile_edit_preview_body':
        'Choose how other players see you in matches and search.',
    'profile_display_helper': 'Use the name you want shown on leaderboards.',
    'profile_display_error': 'Enter at least 2 characters.',
    'profile_search_name': 'Search name',
    'profile_search_helper':
        'Lowercase letters, numbers and underscore are allowed.',
    'profile_search_error': 'Use 3-20 letters, numbers or underscore.',
    'profile_discovery_title': 'Let players find me',
    'profile_discovery_on': 'Other players can find you by name or Friend ID.',
    'profile_discovery_off':
        'New players cannot find you in search. Friends stay connected.',
    'friend_id': 'Friend ID',
    'copy_friend_id': 'Copy Friend ID',
    'discoverable_by_players': 'Discoverable by other players',
    'discoverable_by_players_body':
        'Allow username, display-name and exact Friend ID search. Existing friends remain connected when disabled.',
    'server_wallet_history': 'Server wallet and purchase history',
    'rematch_could_not_start': 'Rematch could not be started.',
    'rematch_invitation_load_failed':
        'The rematch invitation could not be loaded.',
    'rematch_invitation_expired': 'This rematch invitation has expired.',
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
    'account_social': 'Account & social',
    'achievement_badges_info':
        'Earned badges can be attached directly to your frame. Locked badges stay visible here so you always know what can be earned.',
    'all': 'All',
    'auto_current_rank': 'Auto · current rank',
    'avatar_number': 'Avatar %1s',
    'avatars': 'Avatars',
    'badges': 'Badges',
    'choose_country': 'Choose country',
    'choose_country_first': 'Choose a country first.',
    'choose_reactions': 'Choose your reactions',
    'choose_reactions_body':
        'Tap a card to equip it. Tap an equipped card again to remove it from your quick slots.',
    'clear_country': 'Clear country',
    'collection': 'COLLECTION',
    'confirmation_required': 'A confirmation is required.',
    'connection_try_again': 'Check your connection and try again.',
    'country_flag': 'Country flag',
    'country_flag_info':
        'Choose the country you want to represent. It appears before your name in Ranked Ladder and is never inferred from your location.',
    'country_name_ad': 'Andorra',
    'country_name_ae': 'United Arab Emirates',
    'country_name_af': 'Afghanistan',
    'country_name_ag': 'Antigua and Barbuda',
    'country_name_ai': 'Anguilla',
    'country_name_al': 'Albania',
    'country_name_am': 'Armenia',
    'country_name_ao': 'Angola',
    'country_name_aq': 'Antarctica',
    'country_name_ar': 'Argentina',
    'country_name_as': 'American Samoa',
    'country_name_at': 'Austria',
    'country_name_au': 'Australia',
    'country_name_aw': 'Aruba',
    'country_name_ax': 'Åland Islands',
    'country_name_az': 'Azerbaijan',
    'country_name_ba': 'Bosnia and Herzegovina',
    'country_name_bb': 'Barbados',
    'country_name_bd': 'Bangladesh',
    'country_name_be': 'Belgium',
    'country_name_bf': 'Burkina Faso',
    'country_name_bg': 'Bulgaria',
    'country_name_bh': 'Bahrain',
    'country_name_bi': 'Burundi',
    'country_name_bj': 'Benin',
    'country_name_bl': 'Saint Barthélemy',
    'country_name_bm': 'Bermuda',
    'country_name_bn': 'Brunei',
    'country_name_bo': 'Bolivia',
    'country_name_bq': 'Bonaire, Sint Eustatius and Saba',
    'country_name_br': 'Brazil',
    'country_name_bs': 'Bahamas',
    'country_name_bt': 'Bhutan',
    'country_name_bv': 'Bouvet Island',
    'country_name_bw': 'Botswana',
    'country_name_by': 'Belarus',
    'country_name_bz': 'Belize',
    'country_name_ca': 'Canada',
    'country_name_cc': 'Cocos (Keeling) Islands',
    'country_name_cd': 'Congo (DRC)',
    'country_name_cf': 'Central African Republic',
    'country_name_cg': 'Congo',
    'country_name_ch': 'Switzerland',
    'country_name_ci': 'Côte d’Ivoire',
    'country_name_ck': 'Cook Islands',
    'country_name_cl': 'Chile',
    'country_name_cm': 'Cameroon',
    'country_name_cn': 'China',
    'country_name_co': 'Colombia',
    'country_name_cr': 'Costa Rica',
    'country_name_cu': 'Cuba',
    'country_name_cv': 'Cabo Verde',
    'country_name_cw': 'Curaçao',
    'country_name_cx': 'Christmas Island',
    'country_name_cy': 'Cyprus',
    'country_name_cz': 'Czechia',
    'country_name_de': 'Germany',
    'country_name_dj': 'Djibouti',
    'country_name_dk': 'Denmark',
    'country_name_dm': 'Dominica',
    'country_name_do': 'Dominican Republic',
    'country_name_dz': 'Algeria',
    'country_name_ec': 'Ecuador',
    'country_name_ee': 'Estonia',
    'country_name_eg': 'Egypt',
    'country_name_eh': 'Western Sahara',
    'country_name_er': 'Eritrea',
    'country_name_es': 'Spain',
    'country_name_et': 'Ethiopia',
    'country_name_fi': 'Finland',
    'country_name_fj': 'Fiji',
    'country_name_fk': 'Falkland Islands',
    'country_name_fm': 'Micronesia, Federated States of',
    'country_name_fo': 'Faroe Islands',
    'country_name_fr': 'France',
    'country_name_ga': 'Gabon',
    'country_name_gb': 'United Kingdom',
    'country_name_gd': 'Grenada',
    'country_name_ge': 'Georgia',
    'country_name_gf': 'French Guiana',
    'country_name_gg': 'Guernsey',
    'country_name_gh': 'Ghana',
    'country_name_gi': 'Gibraltar',
    'country_name_gl': 'Greenland',
    'country_name_gm': 'Gambia',
    'country_name_gn': 'Guinea',
    'country_name_gp': 'Guadeloupe',
    'country_name_gq': 'Equatorial Guinea',
    'country_name_gr': 'Greece',
    'country_name_gs': 'South Georgia and the South Sandwich Islands',
    'country_name_gt': 'Guatemala',
    'country_name_gu': 'Guam',
    'country_name_gw': 'Guinea-Bissau',
    'country_name_gy': 'Guyana',
    'country_name_hk': 'Hong Kong',
    'country_name_hm': 'Heard Island and McDonald Islands',
    'country_name_hn': 'Honduras',
    'country_name_hr': 'Croatia',
    'country_name_ht': 'Haiti',
    'country_name_hu': 'Hungary',
    'country_name_id': 'Indonesia',
    'country_name_ie': 'Ireland',
    'country_name_il': 'Israel',
    'country_name_im': 'Isle of Man',
    'country_name_in': 'India',
    'country_name_io': 'British Indian Ocean Territory',
    'country_name_iq': 'Iraq',
    'country_name_ir': 'Iran',
    'country_name_is': 'Iceland',
    'country_name_it': 'Italy',
    'country_name_je': 'Jersey',
    'country_name_jm': 'Jamaica',
    'country_name_jo': 'Jordan',
    'country_name_jp': 'Japan',
    'country_name_ke': 'Kenya',
    'country_name_kg': 'Kyrgyzstan',
    'country_name_kh': 'Cambodia',
    'country_name_ki': 'Kiribati',
    'country_name_km': 'Comoros',
    'country_name_kn': 'Saint Kitts and Nevis',
    'country_name_kp': 'North Korea',
    'country_name_kr': 'South Korea',
    'country_name_kw': 'Kuwait',
    'country_name_ky': 'Cayman Islands',
    'country_name_kz': 'Kazakhstan',
    'country_name_la': 'Laos',
    'country_name_lb': 'Lebanon',
    'country_name_lc': 'Saint Lucia',
    'country_name_li': 'Liechtenstein',
    'country_name_lk': 'Sri Lanka',
    'country_name_lr': 'Liberia',
    'country_name_ls': 'Lesotho',
    'country_name_lt': 'Lithuania',
    'country_name_lu': 'Luxembourg',
    'country_name_lv': 'Latvia',
    'country_name_ly': 'Libya',
    'country_name_ma': 'Morocco',
    'country_name_mc': 'Monaco',
    'country_name_md': 'Moldova',
    'country_name_me': 'Montenegro',
    'country_name_mf': 'Saint Martin (French part)',
    'country_name_mg': 'Madagascar',
    'country_name_mh': 'Marshall Islands',
    'country_name_mk': 'North Macedonia',
    'country_name_ml': 'Mali',
    'country_name_mm': 'Myanmar',
    'country_name_mn': 'Mongolia',
    'country_name_mo': 'Macao',
    'country_name_mp': 'Northern Mariana Islands',
    'country_name_mq': 'Martinique',
    'country_name_mr': 'Mauritania',
    'country_name_ms': 'Montserrat',
    'country_name_mt': 'Malta',
    'country_name_mu': 'Mauritius',
    'country_name_mv': 'Maldives',
    'country_name_mw': 'Malawi',
    'country_name_mx': 'Mexico',
    'country_name_my': 'Malaysia',
    'country_name_mz': 'Mozambique',
    'country_name_na': 'Namibia',
    'country_name_nc': 'New Caledonia',
    'country_name_ne': 'Niger',
    'country_name_nf': 'Norfolk Island',
    'country_name_ng': 'Nigeria',
    'country_name_ni': 'Nicaragua',
    'country_name_nl': 'Netherlands',
    'country_name_no': 'Norway',
    'country_name_np': 'Nepal',
    'country_name_nr': 'Nauru',
    'country_name_nu': 'Niue',
    'country_name_nz': 'New Zealand',
    'country_name_om': 'Oman',
    'country_name_pa': 'Panama',
    'country_name_pe': 'Peru',
    'country_name_pf': 'French Polynesia',
    'country_name_pg': 'Papua New Guinea',
    'country_name_ph': 'Philippines',
    'country_name_pk': 'Pakistan',
    'country_name_pl': 'Poland',
    'country_name_pm': 'Saint Pierre and Miquelon',
    'country_name_pn': 'Pitcairn',
    'country_name_pr': 'Puerto Rico',
    'country_name_ps': 'Palestine',
    'country_name_pt': 'Portugal',
    'country_name_pw': 'Palau',
    'country_name_py': 'Paraguay',
    'country_name_qa': 'Qatar',
    'country_name_re': 'Réunion',
    'country_name_ro': 'Romania',
    'country_name_rs': 'Serbia',
    'country_name_ru': 'Russia',
    'country_name_rw': 'Rwanda',
    'country_name_sa': 'Saudi Arabia',
    'country_name_sb': 'Solomon Islands',
    'country_name_sc': 'Seychelles',
    'country_name_sd': 'Sudan',
    'country_name_se': 'Sweden',
    'country_name_sg': 'Singapore',
    'country_name_sh': 'Saint Helena, Ascension and Tristan da Cunha',
    'country_name_si': 'Slovenia',
    'country_name_sj': 'Svalbard and Jan Mayen',
    'country_name_sk': 'Slovakia',
    'country_name_sl': 'Sierra Leone',
    'country_name_sm': 'San Marino',
    'country_name_sn': 'Senegal',
    'country_name_so': 'Somalia',
    'country_name_sr': 'Suriname',
    'country_name_ss': 'South Sudan',
    'country_name_st': 'Sao Tome and Principe',
    'country_name_sv': 'El Salvador',
    'country_name_sx': 'Sint Maarten (Dutch part)',
    'country_name_sy': 'Syria',
    'country_name_sz': 'Eswatini',
    'country_name_tc': 'Turks and Caicos Islands',
    'country_name_td': 'Chad',
    'country_name_tf': 'French Southern Territories',
    'country_name_tg': 'Togo',
    'country_name_th': 'Thailand',
    'country_name_tj': 'Tajikistan',
    'country_name_tk': 'Tokelau',
    'country_name_tl': 'Timor-Leste',
    'country_name_tm': 'Turkmenistan',
    'country_name_tn': 'Tunisia',
    'country_name_to': 'Tonga',
    'country_name_tr': 'Türkiye',
    'country_name_tt': 'Trinidad and Tobago',
    'country_name_tv': 'Tuvalu',
    'country_name_tw': 'Taiwan',
    'country_name_tz': 'Tanzania',
    'country_name_ua': 'Ukraine',
    'country_name_ug': 'Uganda',
    'country_name_um': 'United States Minor Outlying Islands',
    'country_name_us': 'United States',
    'country_name_uy': 'Uruguay',
    'country_name_uz': 'Uzbekistan',
    'country_name_va': 'Vatican City',
    'country_name_vc': 'Saint Vincent and the Grenadines',
    'country_name_ve': 'Venezuela',
    'country_name_vg': 'Virgin Islands, British',
    'country_name_vi': 'Virgin Islands, U.S.',
    'country_name_vn': 'Vietnam',
    'country_name_vu': 'Vanuatu',
    'country_name_wf': 'Wallis and Futuna',
    'country_name_ws': 'Samoa',
    'country_name_ye': 'Yemen',
    'country_name_yt': 'Mayotte',
    'country_name_za': 'South Africa',
    'country_name_zm': 'Zambia',
    'country_name_zw': 'Zimbabwe',
    'country_rank': 'Country rank',
    'country_saved_flag_hidden':
        'Your country stays saved, but the flag is hidden from the ladder.',
    'default_emotes_restored': 'Default emotes restored.',
    'duel_controls': 'DUEL CONTROLS',
    'emote_afk': 'AFK',
    'emote_angry': 'Angry',
    'emote_bored': 'Bored',
    'emote_bruh': 'BRUH',
    'emote_change_failed': 'That emote could not be changed.',
    'emote_clap': 'Slow Clap',
    'emote_clutch': 'CLUTCH',
    'emote_crown': 'Crown',
    'emote_dizzy': 'Dizzy',
    'emote_equipped_slot': '%1s, equipped in slot %2d',
    'emote_eye_roll': 'Eye Roll',
    'emote_ez': 'EZ',
    'emote_facepalm': 'Facepalm',
    'emote_fire': 'Fire',
    'emote_gg': 'GG',
    'emote_lag': 'LAG',
    'emote_laugh': 'Laugh',
    'emote_love': 'Love',
    'emote_noob': 'NOOB',
    'emote_one_v_one': '1V1',
    'emote_oops': 'OOPS',
    'emote_plotting': 'Plotting',
    'emote_rekt': 'REKT',
    'emote_respect': 'Respect',
    'emote_salty_cry': 'Salty Cry',
    'emote_selection_load_failed': 'Emote selection could not be loaded.',
    'emote_shocked': 'Shocked',
    'emote_shush': 'Shush',
    'emote_smile': 'Smile',
    'emote_smug': 'Smug',
    'emote_victory': 'Victory',
    'emotes': 'Emotes',
    'empty_quick_emote_slot': 'Empty quick emote slot %1d',
    'fantasy_subtitle': 'A long 16×16 board with symbols 1–9 and A–G.',
    'flag_before_player_name':
        'Your flag can be shown before your player name.',
    'flag_only_before_name':
        'Only the flag appears before your name. No country abbreviation is shown.',
    'forfeit_match': 'Forfeit match',
    'frame_follows_current_rank':
        'Frame follows your current rank automatically.',
    'frames': 'Frames',
    'generic_try_again_moment': 'Try again in a moment.',
    'keep_one_quick_emote': 'Keep at least one quick emote equipped.',
    'lifetime_rank_coins': '%1d lifetime Rank Coins',
    'match_options': 'MATCH OPTIONS',
    'matches': 'Matches',
    'max_three_frame_badges': 'You can equip up to 3 frame badges.',
    'mute': 'Mute',
    'mute_opponent_emotes': 'Mute opponent emotes',
    'no_country_flag_until_chosen':
        'No country flag will be shown until you choose one.',
    'no_country_found': 'No country found.',
    'no_data_yet': 'No data yet.',
    'no_title': 'No title',
    'open_emotes': 'Open emotes',
    'opponent_turn_waiting': 'OPPONENT’S TURN · Waiting…',
    'overview': 'Overview',
    'performance': 'Performance',
    'permanently_unlocked_rp': 'Permanently unlocked at %1d RP.',
    'platform_connected': 'Platform connected',
    'platform_not_connected': 'Platform not connected',
    'player_account_try_again': 'Player account unavailable. Try again.',
    'prestige_titles': 'Prestige titles',
    'prestige_titles_info':
        'Master and Master I titles are permanent account unlocks. Your actual current rank is always shown separately.',
    'preview': 'Preview',
    'profile_customization': 'Profile customization',
    'profile_not_ready': 'Profile not ready yet.',
    'profile_preview_reconnect': 'Preview mode · reconnect to save changes.',
    'profile_reconnecting_preview':
        'Online profile is reconnecting. All profile options remain previewable.',
    'profile_save_ready_info':
        'Avatars come only from the bundled avatar collection. Rank cosmetics are earned.',
    'profile_server_unavailable_preview':
        'Profile server is unavailable. Preview is local until reconnect.',
    'profile_settings_saved': 'Profile settings saved.',
    'quick_emote_slot_label': '%1s, quick emote slot %2d',
    'quick_emotes': 'Quick Emotes',
    'quick_emotes_limit':
        'You can equip up to 8 quick emotes. Remove one first.',
    'quick_emotes_reorder_body':
        'The same 4 × 2 layout is used when you open emotes during a duel. Hold and drag to reorder.',
    'rank_decoration_giant_slayer_body':
        'Defeat a ranked opponent at least 251 MMR above you.',
    'rank_decoration_giant_slayer_title': 'Giant Slayer',
    'rank_decoration_perfect_ranked_win_body':
        'Win a ranked duel without a mistake or timeout.',
    'rank_decoration_perfect_ranked_win_title': 'Perfect Duel',
    'rank_decoration_perfect_ranked_wins_10_body':
        'Win 10 ranked duels without a mistake or timeout.',
    'rank_decoration_perfect_ranked_wins_10_title': 'Perfect Ten',
    'rank_decoration_rank_gold_body': 'Reach Gold III for the first time.',
    'rank_decoration_rank_gold_title': 'Gold Competitor',
    'rank_decoration_rank_master_body': 'Reach Master III for the first time.',
    'rank_decoration_rank_master_i_body': 'Reach Master I for the first time.',
    'rank_decoration_rank_master_i_title': 'Master I',
    'rank_decoration_rank_master_title': 'Master Competitor',
    'rank_decoration_rank_platinum_body':
        'Reach Platinum III for the first time.',
    'rank_decoration_rank_platinum_title': 'Platinum Competitor',
    'rank_decoration_rank_silver_body': 'Reach Silver III for the first time.',
    'rank_decoration_rank_silver_title': 'Silver Competitor',
    'rank_decoration_ranked_veteran_1000_body': 'Finish 1000 ranked duels.',
    'rank_decoration_ranked_veteran_1000_title': 'Legendary Veteran',
    'rank_decoration_ranked_veteran_100_body': 'Finish 100 ranked duels.',
    'rank_decoration_ranked_veteran_100_title': 'Ranked Veteran',
    'rank_decoration_ranked_veteran_500_body': 'Finish 500 ranked duels.',
    'rank_decoration_ranked_veteran_500_title': 'Elite Veteran',
    'rank_decoration_undefeated_10_body':
        'Finish 10 ranked duels in a row without a loss.',
    'rank_decoration_undefeated_10_title': 'Unbeaten 10',
    'rank_decoration_undefeated_25_body':
        'Finish 25 ranked duels in a row without a loss.',
    'rank_decoration_undefeated_25_title': 'Unbeaten 25',
    'rank_decoration_undefeated_50_body':
        'Finish 50 ranked duels in a row without a loss.',
    'rank_decoration_undefeated_50_title': 'Unbeaten 50',
    'rank_decoration_win_streak_10_body': 'Win 10 ranked duels in a row.',
    'rank_decoration_win_streak_10_title': 'Ten Win Streak',
    'rank_decoration_win_streak_25_body': 'Win 25 ranked duels in a row.',
    'rank_decoration_win_streak_25_title': 'Twenty Five Win Streak',
    'rank_decoration_win_streak_5_body': 'Win 5 ranked duels in a row.',
    'rank_decoration_win_streak_5_title': 'Five Win Streak',
    'rank_frames_info':
        'Every division has its own frame. Rank rewards are first-time-only and cannot be farmed by dropping and climbing again.',
    'rank_points_format': '%1s · %2d RP',
    'rarity_common': 'COMMON',
    'rarity_epic': 'EPIC',
    'rarity_legendary': 'LEGENDARY',
    'rarity_rare': 'RARE',
    'reactions': 'Reactions',
    'refresh_profile': 'Refresh profile',
    'restore_default_emotes': 'Restore default emotes',
    'saving': 'Saving',
    'search_country': 'Search country',
    'service_busy_try_again': 'Service busy. Try again shortly.',
    'show_flag_ranked_ladder': 'Show flag on Ranked Ladder',
    'status': 'Status',
    'sudoku_player': 'Sudoku Player',
    'taunts': 'Taunts',
    'three_achievement_slots': '3 achievement slots',
    'titles': 'Titles',
    'unlock_reaching_rp': 'Unlock by reaching %1d RP.',
    'unmute': 'Unmute',
    'unmute_opponent_emotes': 'Unmute opponent emotes',
    'your_loadout': 'YOUR LOADOUT',
    'your_turn_make_move': 'YOUR TURN · Make your move',
    'achievement_highlights_subtitle': 'View your highlights and milestones',
    'achievement_label': 'Achievements',
    'all_caught_up': 'All caught up',
    'best_streak': 'Best streak',
    'best_unbeaten': 'Best unbeaten',
    'coin_fee_each_player': '%1d Coin from each player',
    'competitive_progression': 'Competitive progression',
    'find_friends': 'Find friends',
    'find_players': 'Find players',
    'games_label': 'Games',
    'global_upper': 'GLOBAL',
    'incoming_challenges_body': 'Incoming duel challenges will appear here.',
    'last_played': 'Last played',
    'leave_penalty_rp': 'Includes -%1d RP leave penalty.',
    'leave_ready_room': 'Leave ready room',
    'leave_ready_room_body':
        'You will leave this duel room. The match will not start from this screen.',
    'leave_ready_room_question': 'Leave ready room?',
    'leave_room': 'Leave room',
    'level_number': 'Level %1d',
    'loading_player_rankings': 'Loading player rankings…',
    'match_found': 'Match found',
    'matchmaking_info': 'Matchmaking info',
    'native_platform_services': 'Native platform services',
    'no_active_challenges': 'No active challenges',
    'no_friends_body':
        'Add friends to challenge, compare scores and climb the ranks together.',
    'no_friends_yet': 'No friends yet',
    'no_recent_opponents': 'No recent opponents',
    'opponent_found': 'Opponent found',
    'opponent_matched_near_level': '%1s matched near your competitive level.',
    'opponent_ready_confirm': '%1s is ready. Confirm when you are ready.',
    'opponent_search': 'Opponent search',
    'opponent_search_body':
        'We look for an available player close to your competitive level. Keep this screen open while matchmaking is active.',
    'platform_global_compete_subtitle':
        'Compete with the best players worldwide',
    'play_games_short': 'Play Games',
    'player_id_copied': 'Player ID copied',
    'players_ready_count': '%1d/2 players ready',
    'profile_avatar_count': '%1d avatars',
    'profile_badge_policy':
        'Rank frames and achievement badges are earned, not purchased. You can equip up to 3 earned badges on your frame. %1d/3 badge slots are currently in use.',
    'profile_style': 'Profile style',
    'profile_style_subtitle': 'Avatar, rank frame, badges and country',
    'quick_emote_slots_count': '%1d slots',
    'quick_emotes_profile_subtitle':
        'Choose and order your 8 quick duel emotes',
    'rank_points': 'Rank Points',
    'rank_points_auto_update': 'Rank Points will update automatically.',
    'rank_points_division_progress': 'Rank Points and division progress',
    'rank_win_rate_line': '%1s · %2d% wins',
    'ranked_label': 'Ranked',
    'ready_room_options': 'READY ROOM OPTIONS',
    'ready_upper': 'READY',
    'rematch_request_seconds': '%1s wants a rematch · %2ds',
    'repeat_opponent_no_rp':
        'Repeat-opponent protection: no farmable RP this match.',
    'repeat_opponent_reduced_rp':
        'Repeat-opponent protection reduced positive RP.',
    'rp_above_master_i': '%1d RP above Master I',
    'rp_progress_fraction': '%1d/%2d RP',
    'rp_signed_value': '%1s%2d RP',
    'rp_to_rank': '%1d RP to %2s',
    'rp_value': '%1d RP',
    'search_username_friend_id': 'Search username or Friend ID',
    'searching_for_opponent_multiline': 'Searching\nfor opponent',
    'second_confirmation_required': 'A second confirmation is required.',
    'seconds_value': '%1d s',
    'social_services_init_failed':
        'Social services could not be initialized. Please try again.',
    'unranked': 'Unranked',
    'view': 'View',
    'view_challenge': 'View challenge',
    'visible_rp_rank_info':
        'Visible RP determines your displayed rank. Matchmaking skill stays hidden.',
    'vs': 'VS',
    'waiting_both_players': 'Waiting for both players to confirm',
    'wants_rematch': 'wants a rematch',
    'wins_label': 'Wins',
    'you_upper': 'YOU',
    'rank_points_short': 'RP',
    'online_challenges_channel_name': 'Online challenges',
    'online_challenges_channel_description':
        'Invitations and updates for online Sudoku challenges and rematches.',
    'push_challenge_accepted_title': 'Challenge accepted',
    'push_challenge_accepted_body':
        'Your opponent accepted. The duel room is ready.',
    'push_challenge_declined_title': 'Challenge declined',
    'push_challenge_declined_body':
        'Your opponent declined the Sudoku challenge.',
    'push_challenge_cancelled_title': 'Challenge cancelled',
    'push_challenge_cancelled_body':
        'The pending Sudoku challenge was cancelled.',
    'push_challenge_updated_title': 'Challenge updated',
    'push_challenge_updated_body': 'Your Sudoku challenge status changed.',
    'push_friend_request_title': 'New friend request',
    'push_friend_request_body': 'A player sent you a friend request.',
    'push_friend_accepted_title': 'Friend request accepted',
    'push_friend_accepted_body': 'Your friend request was accepted.',
    'push_friend_declined_title': 'Friend request declined',
    'push_friend_declined_body': 'Your friend request was declined.',
    'push_friend_updated_title': 'Friend request updated',
    'push_friend_updated_body': 'Your friend request was updated.',
    'push_rematch_title': 'Rematch invitation',
    'push_rematch_body':
        'A player wants to play again. Open Sudoku Duel to respond.',
    'push_challenge_title': 'New Sudoku challenge',
    'push_challenge_body':
        'A player challenged you. Open Sudoku Duel to respond.',
    'push_online_invitation_title': 'Online invitation',
    'push_online_invitation_body': 'Open Sudoku Duel to continue.',
    'notification_setup_failed': 'Notification setup failed. Please try again.',
    'notification_permission_denied': 'Notification permission was denied.',
    'notification_token_unavailable':
        'Notification registration is temporarily unavailable.',
    'notification_registration_failed':
        'Notification registration failed. Please try again.',
    'rank_emblem_semantics': '%1s rank emblem',
    'reminder_opener_01': 'Your next Sudoku is waiting.',
    'reminder_opener_02': 'A fresh grid just challenged you.',
    'reminder_opener_03': 'Your brain deserves a quick workout.',
    'reminder_opener_04': 'The board is ready when you are.',
    'reminder_opener_05': 'A new puzzle wants your attention.',
    'reminder_opener_06': 'Today’s logic challenge has arrived.',
    'reminder_opener_07': 'Your next winning streak starts here.',
    'reminder_opener_08': 'One clever move can change the board.',
    'reminder_opener_09': 'The Sudoku arena is calling.',
    'reminder_opener_10': 'A quiet challenge is ready for you.',
    'reminder_opener_11': 'Your daily focus break is here.',
    'reminder_opener_12': 'Another puzzle is ready to be conquered.',
    'reminder_challenge_01': 'Can you finish without a single mistake?',
    'reminder_challenge_02': 'Can you beat your latest performance?',
    'reminder_challenge_03': 'Try a harder difficulty this time.',
    'reminder_challenge_04': 'See how far pure logic can take you.',
    'reminder_challenge_05': 'Protect your three-mistake limit.',
    'reminder_challenge_06': 'Build a cleaner winning streak today.',
    'reminder_challenge_07': 'Find the first hidden number now.',
    'reminder_challenge_08': 'Challenge yourself before someone else does.',
    'reminder_challenge_09': 'Prove that this grid cannot stop you.',
    'reminder_challenge_10': 'Turn a few focused minutes into a win.',
    'reminder_challenge_11': 'Solve one row and let momentum take over.',
    'reminder_challenge_12': 'Show the board who is in control.',
    'reminder_closer_01': 'Open Sudoku Duel and take the first move.',
    'reminder_closer_02': 'Your next victory may be one tap away.',
    'reminder_closer_03': 'Start now and keep your streak alive.',
    'reminder_closer_04': 'The challenge only begins when you open it.',
    'reminder_closer_05': 'A focused minute is all you need to begin.',
    'reminder_closer_06': 'Step into the grid and prove it.',
    'reminder_closer_07': 'Play now before the puzzle wins by default.',
    'reminder_closer_08': 'Tap in and claim today’s challenge.',
    'leaderboard_server_unavailable': 'Leaderboard server is unavailable.',
    'no_ranked_players_yet': 'No ranked players yet.',
    'leaderboard_offline_body':
        'Your current rank remains visible locally. Pull down or tap refresh after the backend reconnects.',
    'leaderboard_empty_ranked_body':
        'Complete a ranked duel to enter the RP leaderboard.',
    'matchmaking_cancelling_search': 'Cancelling search...',
    'matchmaking_searching_opponent': 'Searching for opponent...',
    'matchmaking_looking_near_rank': 'Looking for a player near your rank',
    'matchmaking_leaving_queue': 'Leaving the matchmaking queue...',
    'matchmaking_preparing_duel': 'Preparing the duel...',
    'matchmaking_may_take_seconds': 'This may take a few seconds.',
    'matchmaking_tip': 'Tip:',
    'matchmaking_keep_open': 'Keep this screen open while we search.',
    'syncing_your_move': 'Syncing your move',
    'make_your_move': 'Make your move',
    'waiting_for_opponent': 'Waiting for opponent',
    'rp_unavailable': '— RP',
    'ranked_top_division_body':
        'You are at the top division. Keep playing ranked duels to build your peak RP and leaderboard position.',
    'ranked_next_division_body':
        '%1d RP until %2s. Ranked duels change your visible RP and determine your competitive division.',
    'not_configured': 'Not configured',
    'checking_connection': 'Checking connection',
    'game_center': 'Game Center',
    'google_play_games': 'Google Play Games',
    'platform_connects_on_open': 'Connects when a feature is opened',
    'rank_name_label': '%1s rank',
    'your_turn_make_move_compact': 'YOUR TURN · Make your move',
    'opponent_turn_waiting_compact': 'OPPONENT’S TURN · Waiting…',
    'empty': 'Empty',
  };

  final Map<String, String> _values;
  static Future<AppStrings> load() async {
    final values = Map<String, String>.from(english);
    final catalogLocales = defaultTargetPlatform == TargetPlatform.iOS
        ? await _preferredIosLocales()
        : const <Locale>[Locale('en')];
    await _loadStringCatalog(values, catalogLocales);

    // Google Play can provide Android resource translations at runtime.
    // iOS uses only the bundled String Catalog after locale resolution so a
    // native English resource can never overwrite the selected iOS language.
    if (defaultTargetPlatform == TargetPlatform.android) {
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
        // Tests and unsupported platforms use catalog/English fallback.
      } on PlatformException {
        // Localization failure must never block startup.
      }
    }
    return AppStrings._(values);
  }

  static Future<List<Locale>> _preferredIosLocales() async {
    final flutterLocales = PlatformDispatcher.instance.locales;
    try {
      final preferredLanguages = await _channel.invokeListMethod<String>(
        'getPreferredLocales',
      );
      if (preferredLanguages != null && preferredLanguages.isNotEmpty) {
        final nativeLocales = preferredLanguages
            .map(_localeFromLanguageTag)
            .whereType<Locale>()
            .toList(growable: false);
        if (nativeLocales.isNotEmpty) {
          return <Locale>[...nativeLocales, ...flutterLocales];
        }
      }
    } on MissingPluginException {
      // Fall through to Flutter's platform locales.
    } on PlatformException {
      // Fall through to Flutter's platform locales.
    }
    return flutterLocales.isNotEmpty
        ? flutterLocales
        : const <Locale>[Locale('en')];
  }

  static Locale? _localeFromLanguageTag(String rawTag) {
    final tag = rawTag.trim().replaceAll('_', '-');
    if (tag.isEmpty) return null;
    final parts = tag
        .split('-')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return null;

    final language = parts.first.toLowerCase();
    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (part.length == 4 && script == null) {
        script = '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      } else if ((part.length == 2 || part.length == 3) && country == null) {
        country = part.toUpperCase();
      }
    }
    return Locale.fromSubtags(
      languageCode: language,
      scriptCode: script,
      countryCode: country,
    );
  }

  static Future<void> _loadStringCatalog(
    Map<String, String> values,
    List<Locale> preferredLocales,
  ) async {
    try {
      final source = await rootBundle.loadString(_catalogAsset);
      final catalog = jsonDecode(source) as Map<String, dynamic>;
      final catalogStrings = catalog['strings'];
      if (catalogStrings is! Map) return;

      final candidates = _catalogLocaleCandidates(preferredLocales);

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

  static List<String> _catalogLocaleCandidates(List<Locale> preferredLocales) {
    final candidates = <String>[];

    void add(String candidate) {
      if (candidate.isNotEmpty && !candidates.contains(candidate)) {
        candidates.add(candidate);
      }
    }

    for (final locale in preferredLocales) {
      final language = locale.languageCode.toLowerCase();
      final script = locale.scriptCode;
      final country = locale.countryCode?.toUpperCase();

      if (language == 'zh') {
        if (script == 'Hant' ||
            const <String>{'TW', 'HK', 'MO'}.contains(country)) {
          add('zh-Hant');
        } else if (script == 'Hans' ||
            const <String>{'CN', 'SG'}.contains(country)) {
          add('zh-Hans');
        }
      }

      if (script != null && script.isNotEmpty) {
        add('$language-$script');
      }
      if (country != null && country.isNotEmpty) {
        add('$language-$country');
      }
      add(language);
    }

    add('en');
    return candidates;
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
