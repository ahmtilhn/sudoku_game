#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'lib/features/home/professional_home_screen.dart'
text = path.read_text(encoding='utf-8')

single_replacements = {
    "final compact = constraints.maxHeight < 700;\n              final wide = constraints.maxWidth >= 760;":
        "final compact = constraints.maxHeight < 760;\n              final wide =\n                  constraints.maxWidth >= 760 ||\n                  constraints.maxWidth > constraints.maxHeight * 1.35;",
    "height: compact ? 150 : 200,": "height: compact ? 72 : 180,",
    "fontSize: compact ? 34 : 42,": "fontSize: compact ? 28 : 42,",
    "height: 50,": "height: 44,",
    "height: compact ? 110 : 124,": "height: compact ? 84 : 124,",
    "final itemHeight = compact ? 78.0 : 88.0;":
        "final itemHeight = compact ? 58.0 : 88.0;",
    "? 68.0\n              : 78.0": "? 48.0\n              : 78.0",
    "? 52.0\n        : 60.0": "? 38.0\n        : 60.0",
}

for old, new in single_replacements.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'professional_home: expected 1 match, got {count}: {old}')
    text = text.replace(old, new, 1)

old = "height: compact ? 90 : 100,"
count = text.count(old)
if count != 2:
    raise SystemExit(f'professional_home: expected 2 mobile primary heights, got {count}')
text = text.replace(old, "height: compact ? 70 : 100,")

path.write_text(text, encoding='utf-8')
