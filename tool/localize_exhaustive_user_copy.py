#!/usr/bin/env python3
"""Third-pass localization migration for literals missed by exact-match scripts.

This pass uses tolerant regular expressions so formatting-only changes do not
reintroduce user-facing English. It also owns the final release-audit keys that
were not present in the earlier localization catalogs.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_STRINGS = ROOT / 'lib/localization/app_strings.dart'
IOS_CATALOG = ROOT / 'assets/localization/Localizable.xcstrings'

STRINGS: dict[str, str] = {
    'leaderboard_server_unavailable': 'Leaderboard server is unavailable.',
    'no_ranked_players_yet': 'No ranked players yet.',
    'leaderboard_offline_body': 'Your current rank remains visible locally. Pull down or tap refresh after the backend reconnects.',
    'leaderboard_empty_ranked_body': 'Complete a ranked duel to enter the RP leaderboard.',
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
    'ranked_top_division_body': 'You are at the top division. Keep playing ranked duels to build your peak RP and leaderboard position.',
    'ranked_next_division_body': '%1d RP until %2s. Ranked duels change your visible RP and determine your competitive division.',
    'not_configured': 'Not configured',
    'checking_connection': 'Checking connection',
    'game_center': 'Game Center',
    'google_play_games': 'Google Play Games',
    'platform_connects_on_open': 'Connects when a feature is opened',
    'rank_name_label': '%1s rank',
    'your_turn_make_move_compact': 'YOUR TURN · Make your move',
    'opponent_turn_waiting_compact': 'OPPONENT’S TURN · Waiting…',
}


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, source: str) -> None:
    (ROOT / path).write_text(source, encoding='utf-8')


def dart_escape(value: str) -> str:
    return value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n')


def ensure_catalogs() -> None:
    source = APP_STRINGS.read_text(encoding='utf-8')
    existing = set(re.findall(r"^\s*'([a-z0-9_]+)'\s*:", source, re.MULTILINE))
    missing = [(key, value) for key, value in STRINGS.items() if key not in existing]
    if missing:
        marker = "    'empty': 'Empty',\n"
        if marker not in source:
            raise RuntimeError('app_strings insertion marker not found')
        block = ''.join(
            f"    '{key}': '{dart_escape(value)}',\n" for key, value in missing
        )
        APP_STRINGS.write_text(
            source.replace(marker, block + marker, 1),
            encoding='utf-8',
        )

    catalog = json.loads(IOS_CATALOG.read_text(encoding='utf-8'))
    strings = catalog.setdefault('strings', {})
    changed = False
    for key, value in STRINGS.items():
        if key in strings:
            continue
        strings[key] = {
            'localizations': {
                'en': {'stringUnit': {'state': 'translated', 'value': value}},
            },
        }
        changed = True
    if changed:
        IOS_CATALOG.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + '\n',
            encoding='utf-8',
        )


def patch_leaderboards() -> None:
    path = 'lib/features/duel/leaderboards_screen.dart'
    source = read(path)
    source = source.replace(
        "'Leaderboard server is unavailable.'",
        "context.tr('leaderboard_server_unavailable')",
    )
    source = source.replace(
        "'No ranked players yet.'",
        "context.tr('no_ranked_players_yet')",
    )
    source = source.replace(
        "'Your current rank remains visible locally. Pull down or tap refresh after the backend reconnects.'",
        "context.tr('leaderboard_offline_body')",
    )
    source = source.replace(
        "'Complete a ranked duel to enter the RP leaderboard.'",
        "context.tr('leaderboard_empty_ranked_body')",
    )
    write(path, source)


def patch_matchmaking() -> None:
    path = 'lib/features/duel/matchmaking_stage.dart'
    source = read(path)
    source = source.replace("this.difficultyLabel = 'Easy',", "this.difficultyLabel = '',")
    # A default is still useful for tests/preview callers, but the fallback is localized
    # at render time instead of being stored as English in the widget API.
    source = source.replace(
        'widget.difficultyLabel',
        "(widget.difficultyLabel.trim().isEmpty ? context.tr('difficulty_easy') : widget.difficultyLabel)",
    )
    replacements = {
        "'Cancelling search...'": "context.tr('matchmaking_cancelling_search')",
        "'Opponent found'": "context.tr('opponent_found')",
        "'Searching for opponent...'": "context.tr('matchmaking_searching_opponent')",
        "'Cancelling search'": "context.tr('matchmaking_cancelling_search')",
        "'Looking for a player near your rank'": "context.tr('matchmaking_looking_near_rank')",
        "'Leaving the matchmaking queue...'": "context.tr('matchmaking_leaving_queue')",
        "'Preparing the duel...'": "context.tr('matchmaking_preparing_duel')",
        "'This may take a few seconds.'": "context.tr('matchmaking_may_take_seconds')",
        "'Keep this screen open while we search.'": "context.tr('matchmaking_keep_open')",
    }
    for old, new in replacements.items():
        source = source.replace(old, new)
    source = re.sub(
        r"const\s+TextSpan\(\s*text:\s*'Tip:\s*',",
        "TextSpan(\n                  text: '${context.tr('matchmaking_tip')} ',",
        source,
    )
    write(path, source)


def patch_online_duel() -> None:
    path = 'lib/features/duel/online_duel_screen.dart'
    source = read(path)
    source = source.replace("'SENDING MOVE…'", "context.tr('sending_move').toUpperCase()")
    source = source.replace("'Syncing your move'", "context.tr('syncing_your_move')")
    source = source.replace("'Make your move'", "context.tr('make_your_move')")
    source = source.replace("'Waiting for opponent'", "context.tr('waiting_for_opponent')")
    write(path, source)


def patch_ready_room() -> None:
    path = 'lib/features/duel/pre_match_ready_screen.dart'
    source = read(path)
    source = source.replace("'— RP'", "context.tr('rp_unavailable')")
    source = source.replace(
        "'${p!.rating} RP'",
        "context.tr('rp_value', <Object>[p!.rating ?? 0])",
    )
    write(path, source)


def patch_ranked_progress() -> None:
    path = 'lib/features/duel/ranked_progress_screen.dart'
    source = read(path)
    source = source.replace(
        "'You are at the top division. Keep playing ranked duels to build your peak RP and leaderboard position.'",
        "context.tr('ranked_top_division_body')",
    )
    source = source.replace(
        "'${profile.pointsToNext ?? 0} RP until $next. Ranked duels change your visible RP and determine your competitive division.'",
        "context.tr('ranked_next_division_body', <Object>[profile.pointsToNext ?? 0, next])",
    )
    write(path, source)


def patch_platform_surfaces() -> None:
    for path in (
        'lib/features/social/google_play_games_screen.dart',
        'lib/features/social/platform_services_screen.dart',
        'lib/features/social/profile_hub_screen.dart',
    ):
        source = read(path)
        source = source.replace("'Game Center'", "context.tr('game_center')")
        source = source.replace("'Google Play Games'", "context.tr('google_play_games')")
        source = source.replace("'Not configured'", "context.tr('not_configured')")
        source = source.replace("'Checking connection'", "context.tr('checking_connection')")
        source = source.replace(
            "connected ? 'Connected' : 'Connects when a feature is opened'",
            "connected ? context.tr('connected') : context.tr('platform_connects_on_open')",
        )
        write(path, source)


def patch_rank_summary() -> None:
    path = 'lib/features/social/rank_identity_summary_card.dart'
    source = read(path)
    source = source.replace(
        "'${profile.rankName} rank'",
        "context.tr('rank_name_label', <Object>[profile.rankName])",
    )
    write(path, source)


def patch_social_hub() -> None:
    path = 'lib/features/social/social_hub_screen.dart'
    source = read(path)

    source = re.sub(
        r"const\s+Expanded\(\s*child:\s*Text\(\s*'Achievements'\s*,",
        "Expanded(\n                        child: Text(\n                          context.tr('achievement_label'),",
        source,
    )
    source = re.sub(
        r"message:\s*'Add friends to challenge, compare scores and climb the ranks together\.'",
        "message: context.tr('no_friends_body')",
        source,
    )
    stat_keys = {
        'Games': 'games_label',
        'Wins': 'wins_label',
        'Win rate': 'win_rate',
        'Losses': 'losses',
        'Draws': 'draws',
        'Achievements': 'achievement_label',
    }
    for literal, key in stat_keys.items():
        source = re.sub(
            rf"_Stat\(\s*'{re.escape(literal)}'\s*,",
            f"_Stat(context.tr('{key}'),",
            source,
        )
    source = re.sub(
        r"_Pill\(\s*'\$\{rank\?\.rankPoints \?\? 0\} RP'\s*,",
        "_Pill(context.tr('rp_value', <Object>[rank?.rankPoints ?? 0]),",
        source,
    )
    source = re.sub(
        r"'\$\{rank!\.rankName\} · \$\{rank!\.rankPoints\} RP'",
        "context.tr('rank_points_format', <Object>[rank!.rankName, rank!.rankPoints])",
        source,
    )
    write(path, source)


def patch_emote_hub() -> None:
    path = 'lib/services/online_duel_emote_hub.dart'
    source = read(path)
    source = source.replace(
        "'YOUR TURN · Make your move'",
        "context.tr('your_turn_make_move_compact')",
    )
    source = source.replace(
        "'OPPONENT’S TURN · Waiting…'",
        "context.tr('opponent_turn_waiting_compact')",
    )
    write(path, source)


def main() -> int:
    ensure_catalogs()
    patch_leaderboards()
    patch_matchmaking()
    patch_online_duel()
    patch_ready_room()
    patch_ranked_progress()
    patch_platform_surfaces()
    patch_rank_summary()
    patch_social_hub()
    patch_emote_hub()
    print(f'Exhaustive localization migration prepared {len(STRINGS)} final audit keys.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
