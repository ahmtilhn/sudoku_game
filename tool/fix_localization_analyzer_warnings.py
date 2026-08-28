#!/usr/bin/env python3
"""Fix analyzer warnings introduced or exposed by the localization migration.

Keeps compatibility helpers backed by AppStrings and adds awaits where a Future
is returned from inside a try block. No product behavior or ad/session policy is
changed.
"""

from __future__ import annotations

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
    print('Localization analyzer warnings normalized.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
