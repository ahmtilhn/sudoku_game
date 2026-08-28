#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'lib/localization/app_strings.dart'
source = path.read_text(encoding='utf-8')
source = source.replace(
    "'searching_for_opponent_multiline': 'Searching\nfor opponent',",
    "'searching_for_opponent_multiline': 'Searching\\nfor opponent',",
)
path.write_text(source, encoding='utf-8')
print('Dart localization escape sequences normalized.')
