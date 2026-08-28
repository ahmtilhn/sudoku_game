#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'assets/localization/Localizable.xcstrings'
values = {
    'ranked_ladder': 'Ranked ladder',
    'ranked_progress_title': 'Ranked Progress',
    'rank_progression': 'Rank progression',
    'global_rp_leaderboard': 'Global RP leaderboard',
    'current_elo_summary': '%1d ELO · %2d games · %3dW %4dL',
}
catalog = json.loads(path.read_text(encoding='utf-8'))
strings = catalog.setdefault('strings', {})
for key, value in values.items():
    strings.setdefault(key, {
        'localizations': {
            'en': {'stringUnit': {'state': 'translated', 'value': value}}
        }
    })
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Synchronized 5 existing rank keys into the iOS String Catalog.')
