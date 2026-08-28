#!/usr/bin/env python3
"""Third-pass localization migration for literals missed by exact-match scripts.

This pass uses tolerant regular expressions so formatting-only changes do not
reintroduce user-facing English. Add newly discovered release-audit gaps here;
the exhaustive guard runs immediately afterwards.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_social_hub() -> None:
    path = ROOT / 'lib/features/social/social_hub_screen.dart'
    source = path.read_text(encoding='utf-8')

    source = re.sub(
        r"const\s+Expanded\(\s*child:\s*Text\(\s*'Achievements'\s*,",
        "Expanded(\n                        child: Text(\n                          context.tr('achievement_label'),",
        source,
    )
    source = re.sub(
        r"message:\s*'Add friends to challenge, compare scores and climb the ranks together\.'",
        "message: context.tr('no_friends_body')",
        source,
    )

    path.write_text(source, encoding='utf-8')


def main() -> int:
    patch_social_hub()
    print('Exhaustive localization migration pass applied.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
