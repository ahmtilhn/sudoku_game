#!/usr/bin/env python3
"""Close the final literal presentation gaps found after the second-pass audit."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_STRINGS = ROOT / 'lib/localization/app_strings.dart'
IOS_CATALOG = ROOT / 'assets/localization/Localizable.xcstrings'
READY_ROOM = ROOT / 'lib/features/duel/pre_match_ready_screen.dart'

KEY = 'rank_points_short'
VALUE = 'RP'

source = READY_ROOM.read_text(encoding='utf-8')
source = source.replace("label: 'RP',", "label: context.tr('rank_points_short'),")
READY_ROOM.write_text(source, encoding='utf-8')

source = APP_STRINGS.read_text(encoding='utf-8')
existing = set(re.findall(r"^\s*'([a-z0-9_]+)'\s*:", source, re.MULTILINE))
if KEY not in existing:
    marker = "    'empty': 'Empty',\n"
    if marker not in source:
        raise RuntimeError('app_strings insertion marker not found')
    source = source.replace(marker, f"    '{KEY}': '{VALUE}',\n" + marker)
    APP_STRINGS.write_text(source, encoding='utf-8')

catalog = json.loads(IOS_CATALOG.read_text(encoding='utf-8'))
strings = catalog.setdefault('strings', {})
strings.setdefault(
    KEY,
    {'localizations': {'en': {'stringUnit': {'state': 'translated', 'value': VALUE}}}},
)
IOS_CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Final presentation localization gap closed.')
