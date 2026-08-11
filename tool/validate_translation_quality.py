#!/usr/bin/env python3
"""Validate that new online duel translations are not English copies."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets" / "localization" / "Localizable.xcstrings"

ONLINE_KEYS = {
    "waiting_for_ranked_opponent",
    "leaderboards",
    "global",
    "leaderboard_empty",
    "leaderboard_row",
    "refresh",
    "ready",
    "stay",
    "forfeit_and_leave",
    "online_forfeit_title",
    "online_forfeit_body",
    "online_connection_failed",
    "online_waiting_snapshot",
    "connected",
    "reconnecting",
    "your_turn",
    "opponents_turn",
    "online_turn_number",
    "you_won",
    "you_lost",
    "online_final_score",
    "rating_delta",
}

ALLOW_SAME = {"global"}
LOCALES = [
    "tr",
    "de",
    "fr",
    "es",
    "pt",
    "it",
    "nl",
    "pl",
    "ru",
    "uk",
    "ar",
    "hi",
    "id",
    "ja",
    "ko",
    "zh-Hans",
    "zh-Hant",
    "th",
    "vi",
    "bn",
    "ur",
]


def placeholders(value: str) -> list[str]:
    return sorted(re.findall(r"%\d+[$]?[sd]|%\d+[sd]|%%", value))


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.get("strings", {})
    for key in sorted(ONLINE_KEYS):
        entry = strings.get(key)
        if not isinstance(entry, dict):
            fail(f"Missing key: {key}")
        localizations = entry.get("localizations", {})
        english = (
            localizations.get("en", {})
            .get("stringUnit", {})
            .get("value", "")
        )
        if not english:
            fail(f"Missing English value: {key}")
        english_placeholders = placeholders(english)
        for locale in LOCALES:
            value = (
                localizations.get(locale, {})
                .get("stringUnit", {})
                .get("value", "")
            )
            if not value:
                fail(f"{key} missing {locale}")
            if key not in ALLOW_SAME and value == english:
                fail(f"{key} {locale} is still identical to English")
            if placeholders(value) != english_placeholders:
                fail(
                    f"{key} {locale} placeholders differ: "
                    f"{placeholders(value)} != {english_placeholders}"
                )
    print(f"Translation quality validated for {len(ONLINE_KEYS)} online keys.")


if __name__ == "__main__":
    main()
