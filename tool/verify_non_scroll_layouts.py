#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [
    'lib/features/home/professional_home_screen.dart',
    'lib/features/career/career_hub_screen.dart',
    'lib/features/economy/coin_store_screen.dart',
    'lib/features/economy/wallet_history_screen.dart',
    'lib/features/game/enhanced_game_screen.dart',
    'lib/features/game/game_screen.dart',
    'lib/features/settings/ux_settings_screen.dart',
    'lib/features/settings/account_protection_screen.dart',
    'lib/features/settings/service_diagnostics_screen.dart',
    'lib/features/social/profile_customization_screen.dart',
    'lib/features/social/profile_hub_screen.dart',
    'lib/features/tutorial/tutorial_screen.dart',
]

FORBIDDEN = (
    'SingleChildScrollView(',
    'CustomScrollView(',
    'ListView(',
    'ListView.builder(',
    'ListView.separated(',
    'RefreshIndicator(',
)

for relative in TARGETS:
    text = (ROOT / relative).read_text(encoding='utf-8')
    for forbidden in FORBIDDEN:
        if forbidden in text:
            raise SystemExit(f'{relative}: forbidden scroll marker {forbidden}')

print('non-scroll layout verification passed')
