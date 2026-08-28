#!/usr/bin/env python3
"""Reject raw technical failures rendered by user-facing Flutter screens."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (ROOT / "lib" / "features", ROOT / "lib" / "widgets")

RAW_RENDER_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "raw exception string",
        re.compile(r"\b(?:_?error|snapshot\.error)\s*\.toString\s*\(\s*\)"),
    ),
    (
        "raw exception message",
        re.compile(
            r"(?:Text|SelectableText|SnackBar|content\s*:|message\s*:|_error\s*=)"
            r"[^;\n]{0,180}\b(?:_?error|snapshot\.error)\s*\.message\b"
        ),
    ),
    (
        "raw error interpolation",
        re.compile(
            r"(?:Text|SelectableText|SnackBar|context\.tr)"
            r"[^;\n]{0,220}\$\{?(?:_?error|snapshot\.error)\}?"
        ),
    ),
    (
        "raw error argument",
        re.compile(
            r"context\.tr\([^;\n]{0,240}<Object>\[[^\]]*"
            r"(?:_?error|snapshot\.error)"
        ),
    ),
)


ADDITIONAL_RAW_RENDER_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "raw status/error state",
        re.compile(
            r"\b(?:_error|errorText|_statusMessage)\s*=\s*"
            r"(?:_?error|snapshot\.error)\s*\.\s*(?:message|toString\s*\(\s*\))"
        ),
    ),
    (
        "raw returned error message",
        re.compile(r"\breturn\s+(?:_?error|snapshot\.error)\s*\.\s*message\b"),
    ),
    (
        "unsafe raw error fallback",
        re.compile(r"\bfallback\s*:\s*(?:_?error|snapshot\.error)\s*\.\s*message\b"),
    ),
    (
        "raw ternary error message",
        re.compile(r":\s*(?:_?error|snapshot\.error)\s*\.\s*message\s*[;,]"),
    ),
    (
        "raw snackbar/helper error message",
        re.compile(
            r"\b(?:_snack|Text)\s*\(\s*(?:_?error|snapshot\.error)\s*\.\s*"
            r"(?:message|toString\s*\(\s*\))"
        ),
    ),
)

PUSH_SERVICE_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "raw push registration exception",
        re.compile(
            r"lastRegistrationError\.value\s*=\s*"
            r"(?:_?error)\s*\.\s*(?:message|toString\s*\(\s*\))"
        ),
    ),
    (
        "remote push title rendered directly",
        re.compile(r"message\.notification\?\.title"),
    ),
    (
        "remote push body rendered directly",
        re.compile(r"message\.notification\?\.body"),
    ),
)

FORBIDDEN_LITERAL_TERMS = (
    "SOCIAL_BACKEND_URL",
    "Deploy the social backend",
    "Cloudflare Worker",
    "Firebase UID",
    "Backend HTTP",
    "DEVELOPER_ERROR",
    "OAuth client",
    "SHA-1",
    "SHA-256",
)

SAFE_ERROR_FRAGMENT = "UserSafeError.message"


def without_line_comments(source: str) -> str:
    lines: list[str] = []
    for line in source.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//") or stripped.startswith("import "):
            lines.append("")
            continue
        lines.append(line.split("//", 1)[0])
    return "\n".join(lines)


def quoted_literals(source: str) -> list[tuple[int, str]]:
    result: list[tuple[int, str]] = []
    pattern = re.compile(r"(?P<quote>['\"])(?P<value>(?:\\.|(?!\1).)*)\1")
    for match in pattern.finditer(source):
        line = source.count("\n", 0, match.start()) + 1
        result.append((line, match.group("value")))
    return result


def main() -> int:
    violations: list[str] = []
    for scan_root in SCAN_ROOTS:
        for path in sorted(scan_root.rglob("*.dart")):
            source = without_line_comments(path.read_text(encoding="utf-8"))
            relative = path.relative_to(ROOT)
            for label, pattern in RAW_RENDER_PATTERNS + ADDITIONAL_RAW_RENDER_PATTERNS:
                for match in pattern.finditer(source):
                    excerpt = match.group(0)
                    if SAFE_ERROR_FRAGMENT in excerpt:
                        continue
                    line = source.count("\n", 0, match.start()) + 1
                    excerpt = " ".join(excerpt.split())[:180]
                    violations.append(
                        f"{relative}:{line}: {label}: {excerpt}"
                    )
            for line, literal in quoted_literals(source):
                for term in FORBIDDEN_LITERAL_TERMS:
                    if term.lower() in literal.lower():
                        violations.append(
                            f"{relative}:{line}: technical user-facing literal: {term}"
                        )

    push_path = ROOT / "lib" / "services" / "push_notification_service.dart"
    push_source = without_line_comments(push_path.read_text(encoding="utf-8"))
    for label, pattern in PUSH_SERVICE_PATTERNS:
        for match in pattern.finditer(push_source):
            line = push_source.count("\n", 0, match.start()) + 1
            excerpt = " ".join(match.group(0).split())[:180]
            violations.append(f"{push_path.relative_to(ROOT)}:{line}: {label}: {excerpt}")

    if violations:
        print("User-facing technical error guard failed:")
        for violation in violations:
            print(f"- {violation}")
        print(
            "Map failures through UserSafeError and keep diagnostics in logs or "
            "debug-only tooling."
        )
        return 1

    print("User-facing screens contain no raw technical error output.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
