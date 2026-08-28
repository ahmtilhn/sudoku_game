#!/usr/bin/env python3
"""Guard notification/reminder/accessibility copy that lives outside widgets."""

from __future__ import annotations

import ast
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'tool/localize_non_widget_user_copy.py'


def required_keys() -> set[str]:
    tree = ast.parse(MIGRATION.read_text(encoding='utf-8'))
    for node in tree.body:
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == 'STRINGS':
            value = ast.literal_eval(node.value)
            return set(value)
    raise RuntimeError('STRINGS catalog not found')


def main() -> int:
    errors: list[str] = []
    keys = required_keys()

    dart = (ROOT / 'lib/localization/app_strings.dart').read_text(encoding='utf-8')
    dart_keys = set(re.findall(r"^\s*'([a-z0-9_]+)'\s*:", dart, re.MULTILINE))
    missing = sorted(keys - dart_keys)
    if missing:
        errors.append('Dart missing: ' + ', '.join(missing))

    ios = json.loads((ROOT / 'assets/localization/Localizable.xcstrings').read_text(encoding='utf-8'))
    ios_keys = set(ios.get('strings', {}))
    missing = sorted(keys - ios_keys)
    if missing:
        errors.append('iOS catalog missing: ' + ', '.join(missing))

    android_root = ET.parse(ROOT / 'android/app/src/main/res/values/strings.xml').getroot()
    android_keys = {node.attrib.get('name', '') for node in android_root.findall('string')}
    missing = sorted(keys - android_keys)
    if missing:
        errors.append('Android strings missing: ' + ', '.join(missing))

    forbidden = {
        'lib/services/push_notification_service.dart': (
            'New friend request', 'New Sudoku challenge', 'Rematch invitation',
            'Online challenges', 'Notification permission was denied.',
            'FCM registration token is unavailable.',
        ),
        'lib/services/reminder_message_catalog.dart': (
            'Your next Sudoku is waiting.', 'Can you finish without a single mistake?',
            'Open Sudoku Duel and take the first move.',
        ),
        'lib/widgets/rank_emblem.dart': (' rank emblem',),
        'backend/social_worker/src/friend_notifications.ts': (
            'New friend request', 'Friend request accepted', 'Friend request declined',
            'sent you a friend request.', 'accepted your friend request.',
        ),
        'backend/social_worker/src/entry.ts': (
            'Rematch invitation', 'wants to play again. You have 10 seconds to respond.',
        ),
        'backend/social_worker/src/index.ts': (
            'New Sudoku challenge', 'Challenge accepted', 'Challenge declined',
            'Challenge cancelled', 'challenged you on', 'accepted your Sudoku challenge.',
        ),
    }
    for relative, terms in forbidden.items():
        source = (ROOT / relative).read_text(encoding='utf-8')
        for term in terms:
            if term in source:
                errors.append(f'{relative}: hardcoded user copy remains: {term}')

    pbx = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    if '../../assets/localization/Localizable.xcstrings' not in pbx or 'Localizable.xcstrings in Resources' not in pbx:
        errors.append('iOS Runner does not bundle the canonical String Catalog')

    if errors:
        print('Non-widget localization guard failed:')
        for error in errors:
            print(f'- {error}')
        return 1
    print(f'Non-widget user copy is centralized across {len(keys)} required keys.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
