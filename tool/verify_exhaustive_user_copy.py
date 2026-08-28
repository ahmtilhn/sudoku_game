#!/usr/bin/env python3
"""Strict audit for user-visible literals that bypass AppStrings.

The regular localization guard intentionally focuses on common Text/title cases.
This second guard is broader and is meant for release validation: it also checks
presentation data objects, helper widgets, status/result variables, popup copy,
accessibility text, and the non-widget catalogs that can surface notifications.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_STRINGS = ROOT / 'lib/localization/app_strings.dart'

SCAN_ROOTS = (
    ROOT / 'lib' / 'features',
    ROOT / 'lib' / 'widgets',
)
EXTRA_FILES = (
    ROOT / 'lib' / 'models' / 'online_duel_emote_catalog.dart',
    ROOT / 'lib' / 'models' / 'rank_identity_fallback.dart',
    ROOT / 'lib' / 'services' / 'online_duel_emote_hub.dart',
    ROOT / 'lib' / 'services' / 'push_notification_service.dart',
    ROOT / 'lib' / 'services' / 'reminder_message_catalog.dart',
    ROOT / 'lib' / 'services' / 'reminder_notification_service.dart',
)

LOCALIZATION_KEYS = set(
    re.findall(
        r"^\s*'([a-z0-9_]+)'\s*:",
        APP_STRINGS.read_text(encoding='utf-8'),
        flags=re.MULTILINE,
    )
)

STRING_RE = re.compile(
    r"(?P<quote>['\"])(?P<value>(?:\\.|(?!\1).)*)\1",
    re.DOTALL,
)

NAMED_PRESENTATION_ARG_RE = re.compile(
    r"\b(?:"
    r"title|subtitle|body|message|label|metric|tooltip|semanticsLabel|"
    r"semanticLabel|labelText|hintText|helperText|errorText|description|"
    r"eyebrow|placeholder|emptyText|emptyLabel|actionLabel|difficultyLabel|"
    r"statusLabel|statusText|resultTitle|resultSubtitle|defaultTitle|defaultBody"
    r")\s*:\s*$",
    re.DOTALL,
)

PRESENTATION_ASSIGNMENT_RE = re.compile(
    r"\b(?:final|var|const|String\??)\s+"
    r"[A-Za-z0-9_]*(?:text|label|title|subtitle|body|message|tooltip|status|"
    r"caption|description|result)[A-Za-z0-9_]*\s*=\s*[^;]{0,220}$",
    re.IGNORECASE | re.DOTALL,
)

PRESENTATION_GETTER_RE = re.compile(
    r"\b(?:String\s+get|get\s+)[A-Za-z0-9_]*(?:text|label|title|subtitle|"
    r"body|message|tooltip|status|caption|description)[A-Za-z0-9_]*\s*=>"
    r"[^;]{0,220}$",
    re.IGNORECASE | re.DOTALL,
)

DIRECT_PRESENTATION_CALL_RE = re.compile(
    r"(?:Text|SelectableText|TextSpan|SnackBar|Tooltip|Semantics|AlertDialog|"
    r"_Stat|_Pill|_InfoRow|_InfoChip|_EmptyState|_EmptyCard|_SectionTitle|"
    r"_Metric|_ResultMetric|_LeaderboardItem|_ProfileTabData|_ActionTile|"
    r"_SettingTile|_MenuItem|_OptionTile)\s*\([^)]{0,260}$",
    re.DOTALL,
)

USER_STATE_ASSIGNMENT_RE = re.compile(
    r"\b(?:_error|_message|_statusMessage|lastRegistrationError\.value)\s*=\s*"
    r"[^;]{0,220}$",
    re.DOTALL,
)

DEFAULT_USER_PARAM_RE = re.compile(
    r"\b(?:this\.)?[A-Za-z0-9_]*(?:label|title|text|message|status|subtitle|"
    r"body|tooltip)[A-Za-z0-9_]*\s*=\s*$",
    re.IGNORECASE,
)

# Protocol/storage/asset strings are intentionally not localized.
ALLOWED_VALUES = {
    'accepted', 'cancelled', 'declined', 'expired', 'pending', 'matched',
    'searching', 'connected', 'closed', 'failed', 'ranked', 'practice',
    'classic', 'samurai', 'custom', 'auto', 'ios', 'android', 'unknown',
    'game_center', 'google_play_games', 'insufficient_coins',
    'challenge_response', 'friend_request', 'friend_response',
    'challenge', 'rematch', 'room', 'social', 'informational',
}

ASSET_OR_TECH_RE = re.compile(
    r"^(?:assets/|packages/|https?://|wss?://|[A-Za-z0-9_./-]+\.(?:png|jpg|jpeg|webp|svg|json|dart|mp3|wav))",
    re.IGNORECASE,
)

LOCALIZED_EXPRESSION_MARKERS = (
    'context.tr(',
    'context.strings.',
    'AppStrings.current.',
    'AppStrings.english[',
    '_localized(',
    '_copy(',
)


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    lines: list[str] = []
    for line in source.splitlines():
        if line.lstrip().startswith('//'):
            lines.append('')
        else:
            lines.append(line.split('//', 1)[0])
    return '\n'.join(lines)


def has_visible_letters(value: str) -> bool:
    static = re.sub(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_.]*", "", value)
    return re.search(r"[A-Za-zÀ-ÖØ-öø-ÿ]", static) is not None


def should_skip(value: str) -> bool:
    value = value.strip()
    if not value or value in LOCALIZATION_KEYS or value in ALLOWED_VALUES:
        return True
    if any(marker in value for marker in LOCALIZED_EXPRESSION_MARKERS):
        return True
    # STRING_RE intentionally stays lightweight and can see fragments created by
    # quotes inside a Dart interpolation such as:
    #   '${context.tr('key', <Object>[value])}'
    # These fragments are expression syntax, not displayed copy. Never let them
    # block the localization migration.
    if '<Object>[' in value:
        return True
    if value.startswith(('${', '@${')) and value.count('${') > value.count('}'):
        return True
    # Dynamic localization key templates are keys, not displayed English.
    if value.startswith(('country_name_${', 'rarity_${', 'rank_${', 'emote_')):
        return True
    if ASSET_OR_TECH_RE.match(value):
        return True
    # Lowercase identifier-like values are overwhelmingly protocol/config keys.
    if re.fullmatch(r"[a-z][a-z0-9_]*", value):
        return True
    if not has_visible_letters(value):
        return True
    return False


def is_presentation_context(source: str, start: int) -> bool:
    before = source[max(0, start - 320):start]
    line_before = before.rsplit('\n', 1)[-1]
    if NAMED_PRESENTATION_ARG_RE.search(before[-180:]):
        return True
    if DIRECT_PRESENTATION_CALL_RE.search(before):
        return True
    if PRESENTATION_ASSIGNMENT_RE.search(before):
        return True
    if PRESENTATION_GETTER_RE.search(before):
        return True
    if USER_STATE_ASSIGNMENT_RE.search(before):
        return True
    if DEFAULT_USER_PARAM_RE.search(line_before):
        return True
    return False


def scan(path: Path) -> list[str]:
    source = strip_comments(path.read_text(encoding='utf-8'))
    violations: list[str] = []
    for match in STRING_RE.finditer(source):
        value = match.group('value')
        if should_skip(value):
            continue
        if not is_presentation_context(source, match.start()):
            continue
        line = source.count('\n', 0, match.start()) + 1
        excerpt = ' '.join(value.split())[:150]
        violations.append(f'{path.relative_to(ROOT)}:{line}: {excerpt}')
    return violations


def main() -> int:
    paths: set[Path] = set()
    for root in SCAN_ROOTS:
        paths.update(root.rglob('*.dart'))
    paths.update(path for path in EXTRA_FILES if path.exists())

    violations: list[str] = []
    for path in sorted(paths):
        if path == APP_STRINGS:
            continue
        violations.extend(scan(path))

    if violations:
        print('Exhaustive user-facing localization audit failed:')
        for violation in violations:
            print(f'- {violation}')
        print('Every displayed literal above must live in AppStrings and be rendered through localized copy.')
        return 1

    print('Exhaustive user-facing localization audit passed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
