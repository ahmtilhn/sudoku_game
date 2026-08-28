#!/usr/bin/env python3
"""Normalize percent signs for AppStrings' custom positional formatter."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DART = ROOT / 'lib/localization/app_strings.dart'
IOS = ROOT / 'assets/localization/Localizable.xcstrings'
ANDROID = ROOT / 'android/app/src/main/res/values/strings.xml'
KEYS = {'leaderboard_row', 'rank_win_rate_line'}

source = DART.read_text(encoding='utf-8')
for key in KEYS:
    source = re.sub(
        rf"('{re.escape(key)}'\s*:\s*'[^'\n]*)%%([^'\n]*')",
        r'\1%\2',
        source,
    )
DART.write_text(source, encoding='utf-8')

catalog = json.loads(IOS.read_text(encoding='utf-8'))
for key in KEYS:
    definition = catalog.get('strings', {}).get(key)
    if not isinstance(definition, dict):
        continue
    localizations = definition.get('localizations', {})
    if not isinstance(localizations, dict):
        continue
    for localization in localizations.values():
        if not isinstance(localization, dict):
            continue
        unit = localization.get('stringUnit')
        if isinstance(unit, dict) and isinstance(unit.get('value'), str):
            unit['value'] = unit['value'].replace('%%', '%')
IOS.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

android = ANDROID.read_text(encoding='utf-8')
for key in KEYS:
    android = re.sub(
        rf'(<string\s+name="{re.escape(key)}"[^>]*>[^<]*)%%([^<]*</string>)',
        r'\1%\2',
        android,
    )
ANDROID.write_text(android, encoding='utf-8')
print('Percent localization literals normalized.')
