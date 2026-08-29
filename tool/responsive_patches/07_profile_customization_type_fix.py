#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'lib/features/social/profile_customization_screen.dart'
text = path.read_text(encoding='utf-8')
old = 'final RankDecorationState decoration;'
new = 'final RankDecoration decoration;'
if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    raise SystemExit('profile customization decoration type marker missing')
path.write_text(text, encoding='utf-8')
