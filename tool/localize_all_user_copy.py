#!/usr/bin/env python3
"""One-shot migration of remaining production user copy into app_strings.dart.

The script is intentionally deterministic and idempotent enough for a CI retry.
It migrates the known presentation/catalog leaks discovered by the full UI audit,
then synchronizes the iOS String Catalog.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_STRINGS = ROOT / "lib/localization/app_strings.dart"
IOS_CATALOG = ROOT / "assets/localization/Localizable.xcstrings"

STRINGS: dict[str, str] = {
    # Shared UX copy.
    "fantasy_subtitle": "A long 16×16 board with symbols 1–9 and A–G.",
    "generic_try_again_moment": "Try again in a moment.",
    "connection_try_again": "Check your connection and try again.",
    "player_account_try_again": "Player account unavailable. Try again.",
    "service_busy_try_again": "Service busy. Try again shortly.",
    "profile_not_ready": "Profile not ready yet.",
    "platform_connected": "Platform connected",
    "platform_not_connected": "Platform not connected",
    "overview": "Overview",
    "performance": "Performance",
    "account_social": "Account & social",
    "matches": "Matches",
    "country_rank": "Country rank",
    "no_data_yet": "No data yet.",
    # Emotes and duel controls.
    "emotes": "Emotes",
    "restore_default_emotes": "Restore default emotes",
    "default_emotes_restored": "Default emotes restored.",
    "emote_selection_load_failed": "Emote selection could not be loaded.",
    "quick_emotes_limit": "You can equip up to 8 quick emotes. Remove one first.",
    "keep_one_quick_emote": "Keep at least one quick emote equipped.",
    "emote_change_failed": "That emote could not be changed.",
    "your_loadout": "YOUR LOADOUT",
    "quick_emotes": "Quick Emotes",
    "quick_emotes_reorder_body": "The same 4 × 2 layout is used when you open emotes during a duel. Hold and drag to reorder.",
    "collection": "COLLECTION",
    "choose_reactions": "Choose your reactions",
    "choose_reactions_body": "Tap a card to equip it. Tap an equipped card again to remove it from your quick slots.",
    "empty_quick_emote_slot": "Empty quick emote slot %1d",
    "quick_emote_slot_label": "%1s, quick emote slot %2d",
    "all": "All",
    "reactions": "Reactions",
    "taunts": "Taunts",
    "status": "Status",
    "emote_equipped_slot": "%1s, equipped in slot %2d",
    "match_options": "MATCH OPTIONS",
    "unmute": "Unmute",
    "mute": "Mute",
    "forfeit_match": "Forfeit match",
    "confirmation_required": "A confirmation is required.",
    "your_turn_make_move": "YOUR TURN · Make your move",
    "opponent_turn_waiting": "OPPONENT’S TURN · Waiting…",
    "duel_controls": "DUEL CONTROLS",
    "opponent": "OPPONENT",
    "unmute_opponent_emotes": "Unmute opponent emotes",
    "mute_opponent_emotes": "Mute opponent emotes",
    "open_emotes": "Open emotes",
    # Profile customization.
    "profile_server_unavailable_preview": "Profile server is unavailable. Preview is local until reconnect.",
    "profile_settings_saved": "Profile settings saved.",
    "profile_customization": "Profile customization",
    "refresh_profile": "Refresh profile",
    "profile_reconnecting_preview": "Online profile is reconnecting. All profile options remain previewable.",
    "avatars": "Avatars",
    "frames": "Frames",
    "badges": "Badges",
    "titles": "Titles",
    "max_three_frame_badges": "You can equip up to 3 frame badges.",
    "country_flag": "Country flag",
    "rank_points_format": "%1s · %2d RP",
    "sudoku_player": "Sudoku Player",
    "avatar_number": "Avatar %1s",
    "lifetime_rank_coins": "%1d lifetime Rank Coins",
    "rank_frames_info": "Every division has its own frame. Rank rewards are first-time-only and cannot be farmed by dropping and climbing again.",
    "auto_current_rank": "Auto · current rank",
    "frame_follows_current_rank": "Frame follows your current rank automatically.",
    "permanently_unlocked_rp": "Permanently unlocked at %1d RP.",
    "unlock_reaching_rp": "Unlock by reaching %1d RP.",
    "three_achievement_slots": "3 achievement slots",
    "achievement_badges_info": "Earned badges can be attached directly to your frame. Locked badges stay visible here so you always know what can be earned.",
    "no_title": "No title",
    "prestige_titles": "Prestige titles",
    "prestige_titles_info": "Master and Master I titles are permanent account unlocks. Your actual current rank is always shown separately.",
    "choose_country": "Choose country",
    "country_flag_info": "Choose the country you want to represent. It appears before your name in Ranked Ladder and is never inferred from your location.",
    "no_country_flag_until_chosen": "No country flag will be shown until you choose one.",
    "flag_before_player_name": "Your flag can be shown before your player name.",
    "clear_country": "Clear country",
    "show_flag_ranked_ladder": "Show flag on Ranked Ladder",
    "choose_country_first": "Choose a country first.",
    "flag_only_before_name": "Only the flag appears before your name. No country abbreviation is shown.",
    "country_saved_flag_hidden": "Your country stays saved, but the flag is hidden from the ladder.",
    "search_country": "Search country",
    "no_country_found": "No country found.",
    "profile_save_ready_info": "Avatars come only from the bundled avatar collection. Rank cosmetics are earned.",
    "profile_preview_reconnect": "Preview mode · reconnect to save changes.",
    "saving": "Saving",
    "preview": "Preview",
    "rarity_common": "COMMON",
    "rarity_rare": "RARE",
    "rarity_epic": "EPIC",
    "rarity_legendary": "LEGENDARY",
    # Rank fallback achievement copy.
    "rank_decoration_undefeated_10_title": "Unbeaten 10",
    "rank_decoration_undefeated_10_body": "Finish 10 ranked duels in a row without a loss.",
    "rank_decoration_undefeated_25_title": "Unbeaten 25",
    "rank_decoration_undefeated_25_body": "Finish 25 ranked duels in a row without a loss.",
    "rank_decoration_undefeated_50_title": "Unbeaten 50",
    "rank_decoration_undefeated_50_body": "Finish 50 ranked duels in a row without a loss.",
    "rank_decoration_win_streak_5_title": "Five Win Streak",
    "rank_decoration_win_streak_5_body": "Win 5 ranked duels in a row.",
    "rank_decoration_win_streak_10_title": "Ten Win Streak",
    "rank_decoration_win_streak_10_body": "Win 10 ranked duels in a row.",
    "rank_decoration_win_streak_25_title": "Twenty Five Win Streak",
    "rank_decoration_win_streak_25_body": "Win 25 ranked duels in a row.",
    "rank_decoration_rank_silver_title": "Silver Competitor",
    "rank_decoration_rank_silver_body": "Reach Silver III for the first time.",
    "rank_decoration_rank_gold_title": "Gold Competitor",
    "rank_decoration_rank_gold_body": "Reach Gold III for the first time.",
    "rank_decoration_rank_platinum_title": "Platinum Competitor",
    "rank_decoration_rank_platinum_body": "Reach Platinum III for the first time.",
    "rank_decoration_rank_master_title": "Master Competitor",
    "rank_decoration_rank_master_body": "Reach Master III for the first time.",
    "rank_decoration_rank_master_i_title": "Master I",
    "rank_decoration_rank_master_i_body": "Reach Master I for the first time.",
    "rank_decoration_giant_slayer_title": "Giant Slayer",
    "rank_decoration_giant_slayer_body": "Defeat a ranked opponent at least 251 MMR above you.",
    "rank_decoration_ranked_veteran_100_title": "Ranked Veteran",
    "rank_decoration_ranked_veteran_100_body": "Finish 100 ranked duels.",
    "rank_decoration_ranked_veteran_500_title": "Elite Veteran",
    "rank_decoration_ranked_veteran_500_body": "Finish 500 ranked duels.",
    "rank_decoration_ranked_veteran_1000_title": "Legendary Veteran",
    "rank_decoration_ranked_veteran_1000_body": "Finish 1000 ranked duels.",
    "rank_decoration_perfect_ranked_win_title": "Perfect Duel",
    "rank_decoration_perfect_ranked_win_body": "Win a ranked duel without a mistake or timeout.",
    "rank_decoration_perfect_ranked_wins_10_title": "Perfect Ten",
    "rank_decoration_perfect_ranked_wins_10_body": "Win 10 ranked duels without a mistake or timeout.",
}

EMOTE_LABELS = {
    "smile": "Smile", "laugh": "Laugh", "smug": "Smug", "bored": "Bored",
    "fire": "Fire", "crown": "Crown", "shocked": "Shocked", "respect": "Respect",
    "angry": "Angry", "clap": "Slow Clap", "facepalm": "Facepalm", "eye_roll": "Eye Roll",
    "shush": "Shush", "salty_cry": "Salty Cry", "love": "Love", "plotting": "Plotting",
    "dizzy": "Dizzy", "victory": "Victory", "gg": "GG", "ez": "EZ", "noob": "NOOB",
    "oops": "OOPS", "rekt": "REKT", "bruh": "BRUH", "one_v_one": "1V1",
    "clutch": "CLUTCH", "afk": "AFK", "lag": "LAG",
}
STRINGS.update({f"emote_{key}": value for key, value in EMOTE_LABELS.items()})


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    (ROOT / path).write_text(value, encoding="utf-8")


def replace_many(path: str, replacements: list[tuple[str, str]]) -> None:
    source = read(path)
    for old, new in replacements:
        if old not in source:
            # Idempotent retry: the replacement may already be present.
            if new in source:
                continue
            raise RuntimeError(f"Expected source not found in {path}: {old[:100]!r}")
        source = source.replace(old, new)
    write(path, source)


def escape_dart(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def migrate_country_catalog() -> None:
    path = "lib/models/country_catalog.dart"
    source = read(path)
    pattern = re.compile(r"CountryOption\(code: '([A-Z]{2})', name: '((?:\\'|[^'])*)'\)")
    matches = list(pattern.finditer(source))
    if matches:
        for match in matches:
            code = match.group(1)
            name = match.group(2).replace("\\'", "'")
            STRINGS[f"country_name_{code.lower()}"] = name
        source = pattern.sub(lambda m: f"CountryOption(code: '{m.group(1)}')", source)
        source = source.replace(
            "const CountryOption({required this.code, required this.name});\n\n  final String code;\n  final String name;",
            "const CountryOption({required this.code});\n\n  final String code;",
        )
        write(path, source)
        return
    # Retry path: recover country values from the already-populated catalog.
    catalog = json.loads(IOS_CATALOG.read_text(encoding="utf-8"))
    for key, definition in catalog.get("strings", {}).items():
        if key.startswith("country_name_"):
            value = (((definition or {}).get("localizations") or {}).get("en") or {}).get("stringUnit", {}).get("value")
            if isinstance(value, str):
                STRINGS[key] = value


def migrate_avatar_catalog() -> None:
    path = "lib/models/avatar_preset_catalog.dart"
    source = read(path)
    source = source.replace("required this.label,", "required this.number,")
    source = source.replace("final String label;", "final int number;")
    source = re.sub(
        r"\s*label: 'Avatar \$\{number\.toString\(\)\.padLeft\(2, '0'\)\}',",
        "\n        number: number,",
        source,
    )
    write(path, source)


def migrate_emote_catalog() -> None:
    path = "lib/models/online_duel_emote_catalog.dart"
    source = read(path)
    if "../localization/app_strings.dart" not in source:
        source = source.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\n\nimport '../localization/app_strings.dart';\n",
        )
    source = source.replace("required this.label,", "required this.labelKey,")
    source = source.replace("this.shortText,", "this.usesTextFallback = false,")
    source = source.replace("final String label;", "final String labelKey;")
    source = source.replace(
        "final String? shortText;",
        "final bool usesTextFallback;",
    )
    # Update the explanatory comment too so no stale contract remains.
    source = source.replace(
        "/// Optional text fallback for iconic text emotes such as GG / EZ.\n  ///\n  /// [assetPath] takes priority whenever final artwork is bundled.\n  final bool usesTextFallback;",
        "/// Whether the localized label is also used as the visual fallback.\n  ///\n  /// [assetPath] takes priority whenever final artwork is bundled.\n  final bool usesTextFallback;",
    )
    block_pattern = re.compile(r"OnlineDuelEmoteDefinition\((.*?)\n      \)", re.DOTALL)
    def migrate_block(match: re.Match[str]) -> str:
        block = match.group(0)
        id_match = re.search(r"id: '([^']+)'", block)
        label_match = re.search(r"label: '((?:\\'|[^'])*)'", block)
        if id_match and label_match:
            emote_id = id_match.group(1)
            block = block.replace(label_match.group(0), f"labelKey: 'emote_{emote_id}'")
        block = re.sub(r"shortText: '((?:\\'|[^'])*)',", "usesTextFallback: true,", block)
        return block
    source = block_pattern.sub(migrate_block, source)
    source = source.replace(
        "final text = emote.shortText;\n    if (text != null && text.isNotEmpty) {",
        "final text = emote.usesTextFallback ? context.tr(emote.labelKey) : null;\n    if (text != null && text.isNotEmpty) {",
    )
    write(path, source)


def migrate_rank_fallback() -> None:
    path = "lib/models/rank_identity_fallback.dart"
    source = read(path)
    block_pattern = re.compile(r"RankDecoration\((.*?)\n    \)", re.DOTALL)
    def migrate_block(match: re.Match[str]) -> str:
        block = match.group(0)
        id_match = re.search(r"achievementId: '([^']+)'", block)
        if not id_match:
            return block
        achievement_id = id_match.group(1)
        block = re.sub(
            r"title: '((?:\\'|[^'])*)',",
            f"title: 'rank_decoration_{achievement_id}_title',",
            block,
            count=1,
        )
        block = re.sub(
            r"description: '((?:\\'|[^'])*)',",
            f"description: 'rank_decoration_{achievement_id}_body',",
            block,
            count=1,
        )
        return block
    source = block_pattern.sub(migrate_block, source)
    write(path, source)


def migrate_ux_copy() -> None:
    path = "lib/localization/ux_copy.dart"
    source = read(path)
    literals = {
        "'A long 16×16 board with symbols 1–9 and A–G.'": "context.tr('fantasy_subtitle')",
        "'Try again in a moment.'": "context.tr('generic_try_again_moment')",
        "'Check your connection and try again.'": "context.tr('connection_try_again')",
        "'Player account unavailable. Try again.'": "context.tr('player_account_try_again')",
        "'Service busy. Try again shortly.'": "context.tr('service_busy_try_again')",
        "'Profile not ready yet.'": "context.tr('profile_not_ready')",
        "'Platform connected'": "context.tr('platform_connected')",
        "'Platform not connected'": "context.tr('platform_not_connected')",
        "'Overview'": "context.tr('overview')",
        "'Performance'": "context.tr('performance')",
        "'Account & social'": "context.tr('account_social')",
        "'Matches'": "context.tr('matches')",
        "'Losses'": "context.tr('losses')",
        "'Draws'": "context.tr('draws')",
        "'Country rank'": "context.tr('country_rank')",
        "'Achievements'": "context.tr('achievements')",
        "'Loading...'": "context.tr('loading')",
        "'No data yet.'": "context.tr('no_data_yet')",
    }
    for old, new in literals.items():
        source = source.replace(old, new)
    write(path, source)


def migrate_emote_screen() -> None:
    path = "lib/features/social/emote_loadout_screen.dart"
    source = read(path)
    if "../../localization/app_strings.dart" not in source:
        source = source.replace(
            "import 'package:flutter/material.dart';\n\n",
            "import 'package:flutter/material.dart';\n\nimport '../../localization/app_strings.dart';\n",
        )
    replacements = {
        "_error = 'Emote selection could not be loaded.';": "_error = 'emote_selection_load_failed';",
        "_showMessage('You can equip up to 8 quick emotes. Remove one first.');": "_showMessage(context.tr('quick_emotes_limit'));",
        "_showMessage('Keep at least one quick emote equipped.');": "_showMessage(context.tr('keep_one_quick_emote'));",
        "_showMessage('That emote could not be changed.');": "_showMessage(context.tr('emote_change_failed'));",
        "title: 'Emotes',": "title: context.tr('emotes'),",
        "tooltip: 'Restore default emotes',": "tooltip: context.tr('restore_default_emotes'),",
        "_showMessage('Default emotes restored.');": "_showMessage(context.tr('default_emotes_restored'));",
        "_InlineNotice(message: _error!),": "_InlineNotice(message: context.tr(_error!)),",
        "eyebrow: 'YOUR LOADOUT',": "eyebrow: context.tr('your_loadout'),",
        "title: 'Quick Emotes',": "title: context.tr('quick_emotes'),",
        "subtitle:\n                            'The same 4 × 2 layout is used when you open emotes during a duel. Hold and drag to reorder.',": "subtitle: context.tr('quick_emotes_reorder_body'),",
        "const _SectionTitle(\n                        eyebrow: 'COLLECTION',\n                        title: 'Choose your reactions',\n                        subtitle:\n                            'Tap a card to equip it. Tap an equipped card again to remove it from your quick slots.',\n                      ),": "_SectionTitle(\n                        eyebrow: context.tr('collection'),\n                        title: context.tr('choose_reactions'),\n                        subtitle: context.tr('choose_reactions_body'),\n                      ),",
        "? 'Empty quick emote slot ${index + 1}'\n          : '${value.label}, quick emote slot ${index + 1}',": "? context.tr('empty_quick_emote_slot', <Object>[index + 1])\n          : context.tr('quick_emote_slot_label', <Object>[\n              context.tr(value.labelKey),\n              index + 1,\n            ]),",
        "label: 'All',": "label: context.tr('all'),",
        "label: 'Reactions',": "label: context.tr('reactions'),",
        "label: 'Taunts',": "label: context.tr('taunts'),",
        "label: 'Status',": "label: context.tr('status'),",
        "label: '${emote.label}${selected ? ', equipped in slot $slot' : ''}',": "label: selected\n          ? context.tr('emote_equipped_slot', <Object>[\n              context.tr(emote.labelKey),\n              slot,\n            ])\n          : context.tr(emote.labelKey),",
        "emote.label,": "context.tr(emote.labelKey),",
    }
    for old, new in replacements.items():
        source = source.replace(old, new)
    write(path, source)


def migrate_emote_hub() -> None:
    path = "lib/services/online_duel_emote_hub.dart"
    source = read(path)
    if "../localization/app_strings.dart" not in source:
        source = source.replace(
            "import 'package:flutter/material.dart';\n\n",
            "import 'package:flutter/material.dart';\n\nimport '../localization/app_strings.dart';\n",
        )
    source = source.replace("const Expanded(\n                        child: Text(\n                          'MATCH OPTIONS',", "Expanded(\n                        child: Text(\n                          context.tr('match_options'),")
    source = source.replace("tooltip: _hub.muted ? 'Unmute' : 'Mute',", "tooltip: _hub.muted ? context.tr('unmute') : context.tr('mute'),")
    source = source.replace("title: const Text(\n                      'Forfeit match',", "title: Text(\n                      context.tr('forfeit_match'),")
    source = source.replace("subtitle: const Text('A confirmation is required.'),", "subtitle: Text(context.tr('confirmation_required')),")
    source = source.replace("localTurn ? 'YOUR TURN · Make your move' : 'OPPONENT’S TURN · Waiting…',", "localTurn\n                  ? context.tr('your_turn_make_move')\n                  : context.tr('opponent_turn_waiting'),")
    source = source.replace("'DUEL CONTROLS',", "context.tr('duel_controls'),")
    source = source.replace("tooltip: 'Emotes',", "tooltip: context.tr('emotes'),")
    source = source.replace("tooltip: 'Match options',", "tooltip: context.tr('match_options'),")
    source = source.replace("'OPPONENT',", "context.tr('opponent'),")
    source = source.replace("'QUICK EMOTES',", "context.tr('quick_emotes'),")
    source = source.replace("? 'Unmute opponent emotes'\n                            : 'Mute opponent emotes',", "? context.tr('unmute_opponent_emotes')\n                            : context.tr('mute_opponent_emotes'),")
    source = source.replace("label: 'Open emotes',", "label: context.tr('open_emotes'),")
    source = source.replace("label: emote.label,", "label: context.tr(emote.labelKey),")
    write(path, source)


def migrate_profile_screen() -> None:
    path = "lib/features/social/profile_customization_screen.dart"
    source = read(path)
    if "../../localization/app_strings.dart" not in source:
        source = source.replace(
            "import '../../core/user_safe_error.dart';\n",
            "import '../../core/user_safe_error.dart';\nimport '../../localization/app_strings.dart';\n",
        )
    # Remove const where translated values become runtime expressions.
    source = source.replace("const SnackBar(\n          content: Text(\n            'Profile server is unavailable. Preview is local until reconnect.',\n          ),\n        )", "SnackBar(content: Text(context.tr('profile_server_unavailable_preview')))")
    source = source.replace("const SnackBar(content: Text('Profile settings saved.'))", "SnackBar(content: Text(context.tr('profile_settings_saved')))")
    source = source.replace("title: 'Profile customization',", "title: context.tr('profile_customization'),")
    source = source.replace("tooltip: 'Refresh profile',", "tooltip: context.tr('refresh_profile'),")
    source = source.replace("'Online profile is reconnecting. All profile options remain previewable.'", "context.tr('profile_reconnecting_preview')")
    source = source.replace("const Tab(", "Tab(")
    for raw, key in (("Avatars", "avatars"), ("Frames", "frames"), ("Badges", "badges"), ("Titles", "titles"), ("Country", "country")):
        source = source.replace(f"text: '{raw}',", f"text: context.tr('{key}'),")
    source = source.replace("const SnackBar(content: Text('You can equip up to 3 frame badges.'))", "SnackBar(content: Text(context.tr('max_three_frame_badges')))")
    source = source.replace("semanticsLabel: 'Country flag',", "semanticsLabel: context.tr('country_flag'),")
    source = source.replace("'${profile.rankName} · ${profile.rankPoints} RP',", "context.tr('rank_points_format', <Object>[profile.rankName, profile.rankPoints]),")
    source = source.replace("displayName: 'Sudoku Player',", "displayName: context.tr('sudoku_player'),")
    source = source.replace("avatar.label,", "context.tr('avatar_number', <Object>[avatar.number.toString().padLeft(2, '0')]),")
    source = source.replace("title: '${profile.totalLifetimeRankReward} lifetime Rank Coins',", "title: context.tr('lifetime_rank_coins', <Object>[profile.totalLifetimeRankReward]),")
    source = source.replace("body:\n                'Every division has its own frame. Rank rewards are first-time-only and cannot be farmed by dropping and climbing again.',", "body: context.tr('rank_frames_info'),")
    source = source.replace("auto ? 'Auto · current rank' : tier.label,", "auto ? context.tr('auto_current_rank') : tier.label,")
    source = source.replace("? 'Frame follows your current rank automatically.'\n                              : unlocked\n                              ? 'Permanently unlocked at ${tier.minPoints} RP.'\n                              : 'Unlock by reaching ${tier.minPoints} RP.',", "? context.tr('frame_follows_current_rank')\n                              : unlocked\n                              ? context.tr('permanently_unlocked_rp', <Object>[tier.minPoints])\n                              : context.tr('unlock_reaching_rp', <Object>[tier.minPoints]),")
    source = source.replace("return const _InfoCard(\n            icon: Icons.workspace_premium_rounded,\n            title: '3 achievement slots',\n            body:\n                'Earned badges can be attached directly to your frame. Locked badges stay visible here so you always know what can be earned.',\n          );", "return _InfoCard(\n            icon: Icons.workspace_premium_rounded,\n            title: context.tr('three_achievement_slots'),\n            body: context.tr('achievement_badges_info'),\n          );")
    source = source.replace("decoration.title,", "context.tr(decoration.title),")
    source = source.replace("decoration.description,", "context.tr(decoration.description),")
    source = source.replace("const RankTitleOption(key: '', label: 'No title'),", "const RankTitleOption(key: '', label: 'no_title'),")
    source = source.replace("return const _InfoCard(\n            icon: Icons.title_rounded,\n            title: 'Prestige titles',\n            body:\n                'Master and Master I titles are permanent account unlocks. Your actual current rank is always shown separately.',\n          );", "return _InfoCard(\n            icon: Icons.title_rounded,\n            title: context.tr('prestige_titles'),\n            body: context.tr('prestige_titles_info'),\n          );")
    source = source.replace("option.label,", "context.tr(option.label),")
    source = source.replace("const _InfoCard(\n          icon: Icons.public_rounded,\n          title: 'Country flag',\n          body:\n              'Choose the country you want to represent. It appears before your name in Ranked Ladder and is never inferred from your location.',\n        ),", "_InfoCard(\n          icon: Icons.public_rounded,\n          title: context.tr('country_flag'),\n          body: context.tr('country_flag_info'),\n        ),")
    source = source.replace("selected?.name ?? 'Choose country',", "selected == null\n                              ? context.tr('choose_country')\n                              : context.tr('country_name_${selected.code.toLowerCase()}'),")
    source = source.replace("? 'No country flag will be shown until you choose one.'\n                              : 'Your flag can be shown before your player name.',", "? context.tr('no_country_flag_until_chosen')\n                              : context.tr('flag_before_player_name'),")
    source = source.replace("label: const Text('Clear country'),", "label: Text(context.tr('clear_country')),")
    source = source.replace("title: const Text(\n            'Show flag on Ranked Ladder',", "title: Text(\n            context.tr('show_flag_ranked_ladder'),")
    source = source.replace("? 'Choose a country first.'\n                : flagVisible\n                ? 'Only the flag appears before your name. No country abbreviation is shown.'\n                : 'Your country stays saved, but the flag is hidden from the ladder.',", "? context.tr('choose_country_first')\n                : flagVisible\n                ? context.tr('flag_only_before_name')\n                : context.tr('country_saved_flag_hidden'),")
    source = source.replace(".where((country) => country.name.toLowerCase().contains(query))", ".where((country) => context\n                  .tr('country_name_${country.code.toLowerCase()}')\n                  .toLowerCase()\n                  .contains(query))")
    source = source.replace("const Text(\n                  'Choose country',", "Text(\n                  context.tr('choose_country'),")
    source = source.replace("decoration: const InputDecoration(\n                    hintText: 'Search country',", "decoration: InputDecoration(\n                    hintText: context.tr('search_country'),")
    source = source.replace("'No country found.',", "context.tr('no_country_found'),")
    source = source.replace("country.name,", "context.tr('country_name_${country.code.toLowerCase()}'),")
    source = source.replace("? 'Avatars come only from the bundled avatar collection. Rank cosmetics are earned.'\n                  : 'Preview mode · reconnect to save changes.',", "? context.tr('profile_save_ready_info')\n                  : context.tr('profile_preview_reconnect'),")
    source = source.replace("? 'Saving'\n                  : serverReady\n                  ? 'Save'\n                  : 'Preview',", "? context.tr('saving')\n                  : serverReady\n                  ? context.tr('save')\n                  : context.tr('preview'),")
    source = source.replace("tooltip: 'Retry',", "tooltip: context.tr('retry'),")
    source = source.replace("'${reward.amount} Coin${reward.claimed ? ' ✓' : ''}',", "'${context.tr('coin_amount', <Object>[reward.amount])}${reward.claimed ? ' ✓' : ''}',")
    source = source.replace("rarity.toUpperCase(),", "context.tr('rarity_${rarity.toLowerCase()}'),")
    # Preview titles may be localization keys for local fallback data; raw backend
    # values still fall through unchanged through context.tr.
    source = source.replace("Text(\n                    title,", "Text(\n                    context.tr(title),")
    write(path, source)


def add_strings_to_sources() -> None:
    source = APP_STRINGS.read_text(encoding="utf-8")
    marker = "    'empty': 'Empty',\n"
    if marker not in source:
        raise RuntimeError("Could not find app_strings insertion marker")
    existing = set(re.findall(r"^\s*'([a-z0-9_]+)'\s*:", source, re.MULTILINE))
    lines = []
    for key in sorted(STRINGS):
        if key in existing:
            continue
        lines.append(f"    '{key}': '{escape_dart(STRINGS[key])}',\n")
    if lines:
        source = source.replace(marker, "".join(lines) + marker)
        APP_STRINGS.write_text(source, encoding="utf-8")

    catalog = json.loads(IOS_CATALOG.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})
    for key, value in STRINGS.items():
        if key in strings:
            continue
        strings[key] = {
            "localizations": {
                "en": {
                    "stringUnit": {
                        "state": "translated",
                        "value": value,
                    }
                }
            }
        }
    IOS_CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def enable_ci_guard() -> None:
    path = ROOT / ".github/workflows/mobile-ci.yml"
    source = path.read_text(encoding="utf-8")
    needle = "      - name: Verify user-safe messages\n        run: python3 tool/verify_user_facing_messages.py\n"
    addition = needle + "\n      - name: Verify localized user copy\n        run: python3 tool/verify_localized_user_copy.py\n"
    if "Verify localized user copy" not in source:
        if needle not in source:
            raise RuntimeError("Could not find Mobile CI insertion point")
        source = source.replace(needle, addition)
        path.write_text(source, encoding="utf-8")


def main() -> int:
    migrate_country_catalog()
    migrate_avatar_catalog()
    migrate_emote_catalog()
    migrate_rank_fallback()
    migrate_ux_copy()
    migrate_emote_screen()
    migrate_emote_hub()
    migrate_profile_screen()
    add_strings_to_sources()
    enable_ci_guard()
    print(f"Localized {len(STRINGS)} catalog entries and enabled the CI guard.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
