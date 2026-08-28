#!/usr/bin/env python3
"""Fix analyzer issues introduced or exposed by the localization migration.

Keeps compatibility helpers backed by AppStrings, adds awaits where a Future is
returned from inside a try block, and normalizes small control-flow/context lint
issues in files touched by the migration. No product policy or game behavior is
changed.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace(path: str, old: str, new: str) -> None:
    target = ROOT / path
    source = target.read_text(encoding='utf-8')
    if old in source:
        target.write_text(source.replace(old, new), encoding='utf-8')


def fix_country_compatibility() -> None:
    path = ROOT / 'lib/models/country_catalog.dart'
    source = path.read_text(encoding='utf-8')
    if "../localization/app_strings.dart" not in source:
        source = "import '../localization/app_strings.dart';\n\n" + source
    marker = '  final String code;\n\n  String get flag => countryFlagEmoji(code);'
    replacement = (
        '  final String code;\n\n'
        "  String get name => AppStrings.english['country_name_${code.toLowerCase()}'] ?? code;\n\n"
        '  String get flag => countryFlagEmoji(code);'
    )
    if marker in source:
        source = source.replace(marker, replacement, 1)
    path.write_text(source, encoding='utf-8')


def wrap_single_line_ifs(path_string: str) -> None:
    """Add braces to simple one-line if statements in migration-touched files."""
    path = ROOT / path_string
    source = path.read_text(encoding='utf-8')
    lines = source.splitlines()
    output: list[str] = []
    pattern = re.compile(r'^(\s*)if \((.*)\) (.+;)$')
    for line in lines:
        match = pattern.match(line)
        if match is None:
            output.append(line)
            continue
        indent, condition, statement = match.groups()
        output.extend(
            [
                f'{indent}if ({condition}) {{',
                f'{indent}  {statement}',
                f'{indent}}}',
            ]
        )
    updated = '\n'.join(output) + ('\n' if source.endswith('\n') else '')
    if updated != source:
        path.write_text(updated, encoding='utf-8')


def fix_emote_loadout_async_context() -> None:
    replace(
        'lib/features/social/emote_loadout_screen.dart',
        """                                    await _loadout.resetToDefaults();
                                    if (mounted) {
                                      _showMessage(context.tr('default_emotes_restored'));
                                    }""",
        """                                    final restoredMessage = context.tr(
                                      'default_emotes_restored',
                                    );
                                    await _loadout.resetToDefaults();
                                    if (mounted) {
                                      _showMessage(restoredMessage);
                                    }""",
    )


def fix_emote_hub_async_context() -> None:
    replace(
        'lib/services/online_duel_emote_hub.dart',
        """    if (action != 'forfeit' || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    await Navigator.of(context).maybePop();""",
        """    if (action != 'forfeit' || !context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;
    await Navigator.of(context).maybePop();""",
    )


def main() -> int:
    fix_country_compatibility()
    replace(
        'lib/services/ads_service.dart',
        'return ConsentInformation.instance.getConsentStatus();',
        'return await ConsentInformation.instance.getConsentStatus();',
    )
    replace(
        'lib/services/ads_service.dart',
        'return ConsentInformation.instance.canRequestAds();',
        'return await ConsentInformation.instance.canRequestAds();',
    )
    replace(
        'lib/services/firebase_session_service.dart',
        'return ensureAnonymousSession(restorePlayGames: false);',
        'return await ensureAnonymousSession(restorePlayGames: false);',
    )
    replace(
        'lib/services/push_notification_service.dart',
        'return _registerCurrentToken();',
        'return await _registerCurrentToken();',
    )

    fix_emote_loadout_async_context()
    fix_emote_hub_async_context()

    for path in (
        'lib/features/social/challenge_invitation_screen.dart',
        'lib/features/social/challenge_waiting_screen.dart',
        'lib/features/social/rematch_invitation_screen.dart',
        'lib/features/social/social_hub_screen.dart',
        'lib/features/social/ux_challenge_invitation_screen.dart',
        'lib/services/online_duel_emote_hub.dart',
    ):
        wrap_single_line_ifs(path)

    print('Localization analyzer issues normalized.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
