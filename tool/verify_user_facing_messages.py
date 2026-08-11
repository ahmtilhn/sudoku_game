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
            for label, pattern in RAW_RENDER_PATTERNS:
                for match in pattern.finditer(source):
                    line = source.count("\n", 0, match.start()) + 1
                    excerpt = " ".join(match.group(0).split())[:180]
                    violations.append(
                        f"{relative}:{line}: {label}: {excerpt}"
                    )
            for line, literal in quoted_literals(source):
                for term in FORBIDDEN_LITERAL_TERMS:
                    if term.lower() in literal.lower():
                        violations.append(
                            f"{relative}:{line}: technical user-facing literal: {term}"
                        )

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
