#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / 'lib/features/social/social_hub_screen.dart'
source = path.read_text(encoding='utf-8')
old = 'if (id.length < 3 || _rankSummaries.containsKey(id) || _rankRequests.contains(id)) continue;'
new = '''if (id.length < 3 ||
          _rankSummaries.containsKey(id) ||
          _rankRequests.contains(id)) {
        continue;
      }'''
if old in source:
    path.write_text(source.replace(old, new), encoding='utf-8')
print('Social hub localization lint normalized.')
