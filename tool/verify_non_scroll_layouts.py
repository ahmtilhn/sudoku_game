#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [
    'lib/features/economy/wallet_history_screen.dart',
    'lib/features/settings/ux_settings_screen.dart',
    'lib/features/settings/account_protection_screen.dart',
    'lib/features/settings/service_diagnostics_screen.dart',
    'lib/features/social/profile_customization_screen.dart',
    'lib/features/tutorial/tutorial_screen.dart',
]

for relative in TARGETS:
    text = (ROOT / relative).read_text(encoding='utf-8')
    for forbidden in ('SingleChildScrollView(', 'CustomScrollView('):
        if forbidden in text:
            raise SystemExit(f'{relative}: forbidden scroll marker {forbidden}')
print('non-scroll layout verification passed')
