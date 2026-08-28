#!/usr/bin/env python3
"""Second-pass migration for presentation literals found by the strict UI audit.

This script is deliberately tolerant of concurrent edits: replacements are only
applied when their exact current form is present. The localization guard runs
immediately afterwards and reports anything an overlapping edit reintroduced.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_STRINGS = ROOT / 'lib/localization/app_strings.dart'
IOS_CATALOG = ROOT / 'assets/localization/Localizable.xcstrings'

STRINGS: dict[str, str] = {
    'level_number': 'Level %1d',
    'rp_value': '%1d RP',
    'rp_signed_value': '%1s%2d RP',
    'rp_above_master_i': '%1d RP above Master I',
    'rp_progress_fraction': '%1d/%2d RP',
    'rp_to_rank': '%1d RP to %2s',
    'global_upper': 'GLOBAL',
    'visible_rp_rank_info': 'Visible RP determines your displayed rank. Matchmaking skill stays hidden.',
    'rank_win_rate_line': '%1s · %2d%% wins',
    'you_upper': 'YOU',
    'loading_player_rankings': 'Loading player rankings…',
    'top_rank': 'Top rank',
    'opponent_search': 'Opponent search',
    'opponent_search_body': 'We look for an available player close to your competitive level. Keep this screen open while matchmaking is active.',
    'matchmaking_info': 'Matchmaking info',
    'searching_for_opponent_multiline': 'Searching\nfor opponent',
    'win_rate': 'Win rate',
    'vs': 'VS',
    'rank_points_auto_update': 'Rank Points will update automatically.',
    'rank_points': 'Rank Points',
    'leave_penalty_rp': 'Includes -%1d RP leave penalty.',
    'repeat_opponent_no_rp': 'Repeat-opponent protection: no farmable RP this match.',
    'repeat_opponent_reduced_rp': 'Repeat-opponent protection reduced positive RP.',
    'rematch_request_seconds': '%1s wants a rematch · %2ds',
    'second_confirmation_required': 'A second confirmation is required.',
    'seconds_short': 's',
    'seconds_value': '%1d s',
    'leave_ready_room_question': 'Leave ready room?',
    'leave_ready_room_body': 'You will leave this duel room. The match will not start from this screen.',
    'leave_room': 'Leave room',
    'opponent_found': 'Opponent found',
    'ready_upper': 'READY',
    'match_found': 'Match found',
    'opponent_ready_confirm': '%1s is ready. Confirm when you are ready.',
    'opponent_matched_near_level': '%1s matched near your competitive level.',
    'waiting_both_players': 'Waiting for both players to confirm',
    'players_ready_count': '%1d/2 players ready',
    'ready_room_options': 'READY ROOM OPTIONS',
    'leave_ready_room': 'Leave ready room',
    'competitive_progression': 'Competitive progression',
    'platform_global_compete_subtitle': 'Compete with the best players worldwide',
    'achievement_highlights_subtitle': 'View your highlights and milestones',
    'social_services_init_failed': 'Social services could not be initialized. Please try again.',
    'wants_rematch': 'wants a rematch',
    'coin_fee_each_player': '%1d Coin from each player',
    'profile_style': 'Profile style',
    'profile_style_subtitle': 'Avatar, rank frame, badges and country',
    'quick_emotes_profile_subtitle': 'Choose and order your 8 quick duel emotes',
    'rank_points_division_progress': 'Rank Points and division progress',
    'native_platform_services': 'Native platform services',
    'profile_avatar_count': '%1d avatars',
    'quick_emote_slots_count': '%1d slots',
    'play_games_short': 'Play Games',
    'profile_badge_policy': 'Rank frames and achievement badges are earned, not purchased. You can equip up to 3 earned badges on your frame. %1d/3 badge slots are currently in use.',
    'player_id_copied': 'Player ID copied',
    'ranked_label': 'Ranked',
    'wins_label': 'Wins',
    'best_streak': 'Best streak',
    'best_unbeaten': 'Best unbeaten',
    'unranked': 'Unranked',
    'games_label': 'Games',
    'friend_id': 'Friend ID',
    'friend_id_copied': 'Friend ID copied',
    'last_played': 'Last played',
    'all_caught_up': 'All caught up',
    'find_players': 'Find players',
    'no_friends_yet': 'No friends yet',
    'no_friends_body': 'Add friends to challenge, compare scores and climb the ranks together.',
    'find_friends': 'Find friends',
    'no_recent_opponents': 'No recent opponents',
    'no_active_challenges': 'No active challenges',
    'incoming_challenges_body': 'Incoming duel challenges will appear here.',
    'view_challenge': 'View challenge',
    'search_username_friend_id': 'Search username or Friend ID',
    'view': 'View',
    'achievement_label': 'Achievements',
}


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, source: str) -> None:
    (ROOT / path).write_text(source, encoding='utf-8')


def ensure_import(source: str, relative: str) -> str:
    statement = f"import '{relative}';"
    if statement in source:
        return source
    package_end = source.rfind("import 'package:")
    if package_end < 0:
        return statement + '\n' + source
    line_end = source.find('\n', package_end)
    return source[: line_end + 1] + statement + '\n' + source[line_end + 1 :]


def replace(path: str, old: str, new: str) -> None:
    source = read(path)
    if old in source:
        source = source.replace(old, new)
        write(path, source)


def regex_replace(path: str, pattern: str, replacement: str, flags: int = 0) -> None:
    source = read(path)
    updated = re.sub(pattern, replacement, source, flags=flags)
    if updated != source:
        write(path, updated)


def migrate_career() -> None:
    replace(
        'lib/features/career/career_hub_screen.dart',
        "'Level ${level.number}'",
        "context.tr('level_number', <Object>[level.number])",
    )


def migrate_leaderboards() -> None:
    path = 'lib/features/duel/leaderboards_screen.dart'
    source = read(path)
    source = source.replace("'${profile.rankPoints} RP'", "context.tr('rp_value', <Object>[profile.rankPoints])")
    source = source.replace("'${profile.pointsInDivision} RP above Master I'", "context.tr('rp_above_master_i', <Object>[profile.pointsInDivision])")
    source = source.replace("'${profile.pointsInDivision}/${profile.divisionSize} RP'", "context.tr('rp_progress_fraction', <Object>[profile.pointsInDivision, profile.divisionSize ?? 0])")
    source = source.replace("'Top rank'", "context.tr('top_rank')")
    source = source.replace("'${profile.pointsToNext ?? 0} RP to ${profile.nextRankName}'", "context.tr('rp_to_rank', <Object>[profile.pointsToNext ?? 0, profile.nextRankName ?? ''])")
    source = source.replace("'GLOBAL'", "context.tr('global_upper')")
    source = source.replace("'Visible RP determines your displayed rank. Matchmaking skill stays hidden.'", "context.tr('visible_rp_rank_info')")
    source = source.replace("semanticsLabel: 'Country flag'", "semanticsLabel: context.tr('country_flag')")
    source = source.replace("'${entry.rankName} · ${(entry.winRate * 100).round()}% wins'", "context.tr('rank_win_rate_line', <Object>[entry.rankName, (entry.winRate * 100).round()])")
    source = source.replace("'${entry.rankPoints} RP'", "context.tr('rp_value', <Object>[entry.rankPoints])")
    source = source.replace("child: const Text(\n        'YOU',", "child: Text(\n        context.tr('you_upper'),")
    source = source.replace("child: const Row(\n        mainAxisAlignment: MainAxisAlignment.center,", "child: Row(\n        mainAxisAlignment: MainAxisAlignment.center,")
    source = source.replace("'Loading player rankings…'", "context.tr('loading_player_rankings')")
    write(path, source)


def migrate_matchmaking() -> None:
    path = 'lib/features/duel/matchmaking_stage.dart'
    source = read(path)
    source = source.replace("const Text(\n                  'Opponent search',", "Text(\n                  context.tr('opponent_search'),")
    source = source.replace("'We look for an available player close to your competitive level. Keep this screen open while matchmaking is active.'", "context.tr('opponent_search_body')")
    source = source.replace("tooltip: 'Matchmaking info'", "tooltip: context.tr('matchmaking_info')")
    source = source.replace("'Searching\\nfor opponent'", "context.tr('searching_for_opponent_multiline')")
    source = source.replace("label: 'Matches'", "label: context.tr('matches')")
    source = source.replace("label: 'Win rate'", "label: context.tr('win_rate')")
    source = source.replace("'${value ?? 0} RP'", "context.tr('rp_value', <Object>[value ?? 0])")
    source = source.replace("'VS'", "context.tr('vs')")
    write(path, source)


def migrate_online_duel() -> None:
    path = 'lib/features/duel/online_duel_screen.dart'
    source = read(path)
    source = source.replace("'VS'", "context.tr('vs')")
    source = source.replace("'Rank Points will update automatically.'", "context.tr('rank_points_auto_update')")
    source = source.replace("'Rank Points'", "context.tr('rank_points')")
    source = source.replace("'${value.rpAfter} RP'", "context.tr('rp_value', <Object>[value.rpAfter])")
    source = source.replace("'$pointsToNext RP to ${next.label}'", "context.tr('rp_to_rank', <Object>[pointsToNext, next.label])")
    source = source.replace("'Includes -${value.abandonmentPenalty} RP leave penalty.'", "context.tr('leave_penalty_rp', <Object>[value.abandonmentPenalty])")
    source = source.replace("'Repeat-opponent protection: no farmable RP this match.'", "context.tr('repeat_opponent_no_rp')")
    source = source.replace("'Repeat-opponent protection reduced positive RP.'", "context.tr('repeat_opponent_reduced_rp')")
    source = source.replace("'${invitation.sender.displayName} wants a rematch · ${seconds}s'", "context.tr('rematch_request_seconds', <Object>[invitation.sender.displayName, seconds])")
    source = source.replace("const Expanded(\n                        child: Text(\n                          'MATCH OPTIONS',", "Expanded(\n                        child: Text(\n                          context.tr('match_options'),")
    source = source.replace("tooltip: hub.muted ? 'Unmute' : 'Mute'", "tooltip: hub.muted ? context.tr('unmute') : context.tr('mute')")
    source = source.replace("title: const Text(\n                      'Forfeit match',", "title: Text(\n                      context.tr('forfeit_match'),")
    source = source.replace("subtitle: const Text('A second confirmation is required.')", "subtitle: Text(context.tr('second_confirmation_required'))")
    source = source.replace("tooltip: 'Emotes'", "tooltip: context.tr('emotes')")
    source = source.replace("tooltip: 'Match options'", "tooltip: context.tr('match_options')")
    source = source.replace("'s'", "context.tr('seconds_short')")
    # Signed RP strings contain nested quote literals, so replace the whole Text
    # expression with a localized sign + integer format.
    source = re.sub(
        r"'\$\{value\.rpDelta >= 0 \? '\+' : ''\}\$\{value\.rpDelta\} RP'",
        "context.tr('rp_signed_value', <Object>[value.rpDelta >= 0 ? '+' : '', value.rpDelta])",
        source,
    )
    source = re.sub(
        r"'\$\{score > 0 \? '\+' : ''\}\$score RP'",
        "context.tr('rp_signed_value', <Object>[score > 0 ? '+' : '', score])",
        source,
    )
    write(path, source)


def migrate_ready_room() -> None:
    path = 'lib/features/duel/pre_match_ready_screen.dart'
    source = read(path)
    source = source.replace("title: const Text('Leave ready room?')", "title: Text(context.tr('leave_ready_room_question'))")
    source = source.replace("content: const Text(\n          'You will leave this duel room. The match will not start from this screen.',\n        )", "content: Text(context.tr('leave_ready_room_body'))")
    source = source.replace("child: const Text('Leave room')", "child: Text(context.tr('leave_room'))")
    source = source.replace("'Opponent found'", "context.tr('opponent_found')")
    source = source.replace("label: 'Matches'", "label: context.tr('matches')")
    source = source.replace("label: 'Win rate'", "label: context.tr('win_rate')")
    source = source.replace("'READY'", "context.tr('ready_upper')")
    source = source.replace("'VS'", "context.tr('vs')")
    source = source.replace("const Text(\n                  'Match found',", "Text(\n                  context.tr('match_found'),")
    source = source.replace("'$opponentName is ready. Confirm when you are ready.'", "context.tr('opponent_ready_confirm', <Object>[opponentName])")
    source = source.replace("'$opponentName matched near your competitive level.'", "context.tr('opponent_matched_near_level', <Object>[opponentName])")
    source = source.replace("'Waiting for both players to confirm'", "context.tr('waiting_both_players')")
    source = source.replace("'2/2 players ready'", "context.tr('players_ready_count', <Object>[2])")
    source = source.replace("'$readyCount/2 players ready'", "context.tr('players_ready_count', <Object>[readyCount])")
    source = source.replace("const Align(\n                    alignment: Alignment.centerLeft,\n                    child: Text(\n                      'READY ROOM OPTIONS',", "Align(\n                    alignment: Alignment.centerLeft,\n                    child: Text(\n                      context.tr('ready_room_options'),")
    source = source.replace("title: const Text(\n                      'Leave ready room',", "title: Text(\n                      context.tr('leave_ready_room'),")
    source = source.replace("subtitle: const Text('A confirmation is required.')", "subtitle: Text(context.tr('confirmation_required'))")
    source = source.replace("tooltip: 'Ready room options'", "tooltip: context.tr('ready_room_options')")
    source = source.replace("player.rating == null ? '— RP' : '${player.rating} RP'", "player.rating == null ? '—' : context.tr('rp_value', <Object>[player.rating ?? 0])")
    # Rows previously marked const may now contain localized runtime text.
    source = source.replace("const Row(\n                    mainAxisAlignment: MainAxisAlignment.center,", "Row(\n                    mainAxisAlignment: MainAxisAlignment.center,")
    write(path, source)


def migrate_ranked_progress() -> None:
    path = 'lib/features/duel/ranked_progress_screen.dart'
    source = read(path)
    source = source.replace("const Text(\n                  'Competitive progression',", "Text(\n                  context.tr('competitive_progression'),")
    write(path, source)


def migrate_home_rematch() -> None:
    replace(
        'lib/features/home/ux_root_screen.dart',
        "'$_seconds s'",
        "context.tr('seconds_value', <Object>[_seconds])",
    )


def migrate_challenge_surfaces() -> None:
    path = 'lib/features/social/challenge_invitation_screen.dart'
    source = read(path)
    source = source.replace("'${rank.rankName} · ${rank.rankPoints} RP'", "context.tr('rank_points_format', <Object>[rank.rankName, rank.rankPoints])")
    source = source.replace("label: 'RP'", "label: context.tr('rank_points_short')")
    write(path, source)

    path = 'lib/features/social/challenge_waiting_screen.dart'
    source = read(path)
    source = source.replace("'${rank.rankName} · ${rank.rankPoints} RP'", "context.tr('rank_points_format', <Object>[rank.rankName, rank.rankPoints])")
    source = source.replace("'${_secondsLeft}s'", "context.tr('seconds_value', <Object>[_secondsLeft])")
    write(path, source)


def migrate_platform_surfaces() -> None:
    path = 'lib/features/social/platform_services_screen.dart'
    source = read(path)
    source = source.replace("subtitle: 'Compete with the best players worldwide'", "subtitle: context.tr('platform_global_compete_subtitle')")
    source = source.replace("subtitle: 'View your highlights and milestones'", "subtitle: context.tr('achievement_highlights_subtitle')")
    write(path, source)

    path = 'lib/features/social/platform_social_screen.dart'
    source = read(path)
    source = source.replace("_error = 'Social services could not be initialized: $error';", "_error = context.tr('social_services_init_failed');")
    write(path, source)


def migrate_rematch_surfaces() -> None:
    for path in (
        'lib/features/social/player_identity_gate.dart',
        'lib/features/social/rematch_invitation_screen.dart',
    ):
        source = read(path)
        if "app_strings.dart" not in source:
            source = ensure_import(source, '../../localization/app_strings.dart')
        source = source.replace("'wants a rematch'", "context.tr('wants_rematch')")
        source = source.replace("'s'", "context.tr('seconds_short')")
        source = source.replace("'$fee Coin from each player'", "context.tr('coin_fee_each_player', <Object>[fee])")
        write(path, source)


def migrate_profile_hub() -> None:
    path = 'lib/features/social/profile_hub_screen.dart'
    source = read(path)
    source = source.replace("title: 'Profile style'", "title: context.tr('profile_style')")
    source = source.replace("subtitle: 'Avatar, rank frame, badges and country'", "subtitle: context.tr('profile_style_subtitle')")
    source = source.replace("metric: '40 avatars'", "metric: context.tr('profile_avatar_count', <Object>[40])")
    source = source.replace("title: 'Emotes'", "title: context.tr('emotes')")
    source = source.replace("subtitle: 'Choose and order your 8 quick duel emotes'", "subtitle: context.tr('quick_emotes_profile_subtitle')")
    source = source.replace("metric: '8 slots'", "metric: context.tr('quick_emote_slots_count', <Object>[8])")
    source = source.replace("subtitle: 'Rank Points and division progress'", "subtitle: context.tr('rank_points_division_progress')")
    source = source.replace("metric: '${_profile?.rankPoints ?? 0} RP'", "metric: context.tr('rp_value', <Object>[_profile?.rankPoints ?? 0])")
    source = source.replace("subtitle: 'Native platform services'", "subtitle: context.tr('native_platform_services')")
    source = source.replace("metric: Platform.isIOS ? 'Native' : 'Play Games'", "metric: Platform.isIOS ? context.tr('native') : context.tr('play_games_short')")
    source = source.replace(
        "'Rank frames and achievement badges are earned, not purchased. '\n              'You can equip up to 3 earned badges on your frame. '\n              '$selectedBadges/3 badge slots are currently in use.'",
        "context.tr('profile_badge_policy', <Object>[selectedBadges])",
    )
    write(path, source)


def migrate_rank_summary() -> None:
    path = 'lib/features/social/rank_identity_summary_card.dart'
    source = read(path)
    source = ensure_import(source, '../../localization/app_strings.dart')
    source = source.replace("const SnackBar(\n                    content: Text('Player ID copied'),", "SnackBar(\n                    content: Text(context.tr('player_id_copied')),")
    source = source.replace("'${profile.rankPoints} RP'", "context.tr('rp_value', <Object>[profile.rankPoints])")
    source = source.replace("'${profile.pointsInDivision} RP above Master I'", "context.tr('rp_above_master_i', <Object>[profile.pointsInDivision])")
    source = source.replace("'${profile.pointsInDivision}/${profile.divisionSize} RP'", "context.tr('rp_progress_fraction', <Object>[profile.pointsInDivision, profile.divisionSize ?? 0])")
    source = source.replace("'Top rank'", "context.tr('top_rank')")
    source = source.replace("'${profile.pointsToNext ?? 0} RP to $next'", "context.tr('rp_to_rank', <Object>[profile.pointsToNext ?? 0, next])")
    source = source.replace("label: 'Ranked'", "label: context.tr('ranked_label')")
    source = source.replace("label: 'Wins'", "label: context.tr('wins_label')")
    source = source.replace("label: 'Win rate'", "label: context.tr('win_rate')")
    source = source.replace("label: 'Best streak'", "label: context.tr('best_streak')")
    source = source.replace("label: 'Best unbeaten'", "label: context.tr('best_unbeaten')")
    write(path, source)


def migrate_social_hub() -> None:
    path = 'lib/features/social/social_hub_screen.dart'
    source = read(path)
    source = source.replace("rank?.rankName ?? 'Unranked'", "rank?.rankName ?? context.tr('unranked')")
    source = source.replace("_Pill('${rank?.rankPoints ?? 0} RP'", "_Pill(context.tr('rp_value', <Object>[rank?.rankPoints ?? 0])")
    source = source.replace("_Stat('Games'", "_Stat(context.tr('games_label')")
    source = source.replace("_Stat('Wins'", "_Stat(context.tr('wins_label')")
    source = source.replace("_Stat('Win rate'", "_Stat(context.tr('win_rate')")
    source = source.replace("_Stat('Losses'", "_Stat(context.tr('losses')")
    source = source.replace("_Stat('Draws'", "_Stat(context.tr('draws')")
    source = source.replace("_Stat('Achievements'", "_Stat(context.tr('achievement_label')")
    source = source.replace("label: 'Friend ID'", "label: context.tr('friend_id')")
    source = source.replace("_snack('Friend ID copied')", "_snack(context.tr('friend_id_copied'))")
    source = source.replace("label: 'Last played'", "label: context.tr('last_played')")
    source = source.replace("const Expanded(child: Text('Achievements'", "Expanded(child: Text(context.tr('achievement_label')")
    source = source.replace("title: 'All caught up'", "title: context.tr('all_caught_up')")
    source = source.replace("action: 'Find players'", "action: context.tr('find_players')")
    source = source.replace("title: 'No friends yet'", "title: context.tr('no_friends_yet')")
    source = source.replace("message: 'Add friends to challenge, compare scores and climb the ranks together.'", "message: context.tr('no_friends_body')")
    source = source.replace("action: 'Find friends'", "action: context.tr('find_friends')")
    source = source.replace("title: 'No recent opponents'", "title: context.tr('no_recent_opponents')")
    source = source.replace("title: 'No active challenges'", "title: context.tr('no_active_challenges')")
    source = source.replace("message: 'Incoming duel challenges will appear here.'", "message: context.tr('incoming_challenges_body')")
    source = source.replace("primaryLabel: 'View challenge'", "primaryLabel: context.tr('view_challenge')")
    source = source.replace("hintText: 'Search username or Friend ID'", "hintText: context.tr('search_username_friend_id')")
    source = source.replace("rank == null ? '@${player.username}' : '${rank!.rankName} · ${rank!.rankPoints} RP'", "rank == null ? '@${player.username}' : context.tr('rank_points_format', <Object>[rank!.rankName, rank!.rankPoints])")
    source = source.replace("rank == null ? '@${challenge.challenger.username}' : '${rank!.rankName} · ${rank!.rankPoints} RP'", "rank == null ? '@${challenge.challenger.username}' : context.tr('rank_points_format', <Object>[rank!.rankName, rank!.rankPoints])")
    source = source.replace("_Meta(Icons.shield_rounded, '${rank?.rankPoints ?? 0} RP'", "_Meta(Icons.shield_rounded, context.tr('rp_value', <Object>[rank?.rankPoints ?? 0])")
    source = source.replace("label: const Text('View')", "label: Text(context.tr('view'))")
    write(path, source)


def add_strings() -> None:
    source = APP_STRINGS.read_text(encoding='utf-8')
    existing = set(re.findall(r"^\s*'([a-z0-9_]+)'\s*:", source, re.MULTILINE))
    marker = "    'empty': 'Empty',\n"
    additions: list[str] = []
    for key in sorted(STRINGS):
        if key in existing:
            continue
        value = STRINGS[key].replace('\\', '\\\\').replace("'", "\\'")
        additions.append(f"    '{key}': '{value}',\n")
    if additions:
        if marker not in source:
            raise RuntimeError('app_strings insertion marker not found')
        source = source.replace(marker, ''.join(additions) + marker)
        APP_STRINGS.write_text(source, encoding='utf-8')

    catalog = json.loads(IOS_CATALOG.read_text(encoding='utf-8'))
    strings = catalog.setdefault('strings', {})
    for key, value in STRINGS.items():
        strings.setdefault(
            key,
            {'localizations': {'en': {'stringUnit': {'state': 'translated', 'value': value}}}},
        )
    IOS_CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main() -> int:
    migrate_career()
    migrate_leaderboards()
    migrate_matchmaking()
    migrate_online_duel()
    migrate_ready_room()
    migrate_ranked_progress()
    migrate_home_rematch()
    migrate_challenge_surfaces()
    migrate_platform_surfaces()
    migrate_rematch_surfaces()
    migrate_profile_hub()
    migrate_rank_summary()
    migrate_social_hub()
    add_strings()
    print(f'Second-pass localization migration prepared {len(STRINGS)} presentation keys.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
