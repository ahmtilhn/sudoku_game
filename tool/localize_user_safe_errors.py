#!/usr/bin/env python3
"""Replace raw backend/exception copy shown by social UI with localized safe errors.

The migration is intentionally idempotent and conservative: it only touches the
small set of user-facing social screens audited by verify_user_facing_messages.py.
Diagnostics remain available through UserSafeError/FlutterError, while release UI
receives localized UX copy instead of backend implementation details.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = (
    'lib/features/social/challenge_invitation_screen.dart',
    'lib/features/social/challenge_waiting_screen.dart',
    'lib/features/social/rematch_invitation_screen.dart',
    'lib/features/social/social_hub_screen.dart',
    'lib/features/social/ux_challenge_invitation_screen.dart',
)
IMPORT = "import '../../core/user_safe_error.dart';"


def migrate(path_string: str) -> bool:
    path = ROOT / path_string
    source = path.read_text(encoding='utf-8')
    original = source

    if IMPORT not in source:
        anchor = "import '../../domain/sudoku.dart';"
        if anchor in source:
            source = source.replace(anchor, f"{IMPORT}\n{anchor}", 1)
        else:
            anchor = "import '../../localization/app_strings.dart';"
            if anchor in source:
                source = source.replace(anchor, f"{IMPORT}\n{anchor}", 1)
            else:
                package_anchor = "import 'package:flutter/material.dart';"
                if package_anchor in source:
                    source = source.replace(
                        package_anchor,
                        f"{package_anchor}\n\n{IMPORT}",
                        1,
                    )

    source = source.replace(
        '_error = error.message',
        '_error = UserSafeError.message(context, error)',
    )
    source = source.replace(
        '_error = error.toString()',
        '_error = UserSafeError.message(context, error)',
    )

    if source != original:
        path.write_text(source, encoding='utf-8')
        return True
    return False


def main() -> int:
    changed = [path for path in TARGETS if migrate(path)]
    print(
        'Mapped raw social errors through UserSafeError in '
        f'{len(changed)} file(s).'
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
