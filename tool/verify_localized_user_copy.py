#!/usr/bin/env python3
"""Reject hardcoded user-facing Flutter copy outside the localization source.

This guard intentionally focuses on presentation code. Domain identifiers,
asset paths, routes, storage keys and network protocol values are not user copy
and therefore remain legal outside app_strings.dart.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_STRINGS = ROOT / "lib" / "localization" / "app_strings.dart"
SCAN_ROOTS = (
    ROOT / "lib" / "features",
    ROOT / "lib" / "widgets",
)
EXTRA_FILES = (
    ROOT / "lib" / "localization" / "ux_copy.dart",
    ROOT / "lib" / "services" / "online_duel_emote_hub.dart",
)

LOCALIZATION_KEYS = set(
    re.findall(
        r"^\s*'([a-z0-9_]+)'\s*:",
        APP_STRINGS.read_text(encoding="utf-8"),
        flags=re.MULTILINE,
    )
)

PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "Text literal",
        re.compile(r"\b(?:const\s+)?(?:Text|SelectableText)\(\s*(['\"])(?P<value>(?:\\.|(?!\1).)*)\1", re.DOTALL),
    ),
    (
        "tooltip literal",
        re.compile(r"\btooltip\s*:\s*(['\"])(?P<value>(?:\\.|(?!\1).)*)\1"),
    ),
    (
        "semantics literal",
        re.compile(r"\b(?:semanticsLabel|label)\s*:\s*(['\"])(?P<value>(?:\\.|(?!\1).)*)\1"),
    ),
    (
        "input copy literal",
        re.compile(r"\b(?:labelText|hintText|helperText|errorText)\s*:\s*(['\"])(?P<value>(?:\\.|(?!\1).)*)\1"),
    ),
    (
        "presentation field literal",
        re.compile(r"\b(?:title|subtitle|body|message|eyebrow)\s*:\s*(['\"])(?P<value>(?:\\.|(?!\1).)*)\1"),
    ),
    (
        "user error assignment",
        re.compile(r"\b(?:_error|_message|_statusMessage)\s*=\s*(['\"])(?P<value>(?:\\.|(?!\1).)*)\1"),
    ),
    (
        "user message call",
        re.compile(r"\b(?:_showMessage|_showSnackBar|_showSnack)\(\s*(['\"])(?P<value>(?:\\.|(?!\1).)*)\1"),
    ),
)

ALLOWED_LITERAL_VALUES = {
    "custom",
    "auto",
}


def without_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    return "\n".join(
        "" if line.lstrip().startswith("//") else line.split("//", 1)[0]
        for line in source.splitlines()
    )


def looks_user_facing(value: str) -> bool:
    value = value.strip()
    if value in ALLOWED_LITERAL_VALUES or value in LOCALIZATION_KEYS:
        return False
    if "context.tr(" in value or "context.strings" in value:
        return False
    # Regex string matching cannot parse nested quote literals inside a Dart
    # interpolation such as '${positive ? '+' : '-'}$amount'. When the captured
    # fragment starts an interpolation but does not contain its closing brace,
    # defer to the surrounding static copy instead of treating variable names as
    # visible words. Complete interpolations such as '${points} RP' are still
    # checked and correctly report the visible 'RP' suffix.
    if value.startswith("${") and "}" not in value:
        return False
    static = re.sub(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_.]*", "", value)
    return re.search(r"[A-Za-zÀ-ÖØ-öø-ÿ]", static) is not None


def scan_file(path: Path) -> list[str]:
    source = without_comments(path.read_text(encoding="utf-8"))
    violations: list[str] = []
    for label, pattern in PATTERNS:
        for match in pattern.finditer(source):
            value = match.group("value")
            if not looks_user_facing(value):
                continue
            line = source.count("\n", 0, match.start()) + 1
            excerpt = " ".join(value.split())[:120]
            violations.append(f"{path.relative_to(ROOT)}:{line}: {label}: {excerpt}")
    return violations


def main() -> int:
    paths: set[Path] = set()
    for root in SCAN_ROOTS:
        paths.update(root.rglob("*.dart"))
    paths.update(path for path in EXTRA_FILES if path.exists())

    violations: list[str] = []
    for path in sorted(paths):
        if path.name == "app_strings.dart":
            continue
        violations.extend(scan_file(path))

    if violations:
        print("Hardcoded user-facing copy guard failed:")
        for violation in violations:
            print(f"- {violation}")
        print(
            "Move the text to lib/localization/app_strings.dart and render it "
            "through context.tr(...)."
        )
        return 1

    print("No hardcoded presentation copy detected outside app_strings.dart.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
