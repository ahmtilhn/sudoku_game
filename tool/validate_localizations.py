#!/usr/bin/env python3
"""Validate that every localization source exposes the same string keys."""

from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DART_PATH = ROOT / "lib" / "localization" / "app_strings.dart"
ANDROID_PATH = (
    ROOT
    / "android"
    / "app"
    / "src"
    / "main"
    / "res"
    / "values"
    / "strings.xml"
)
IOS_CATALOG_PATH = (
    ROOT / "assets" / "localization" / "Localizable.xcstrings"
)


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def dart_keys() -> set[str]:
    source = DART_PATH.read_text(encoding="utf-8")
    start = source.find("static const Map<String, String> english")
    if start < 0:
        fail("Could not find the English localization map in app_strings.dart")
    end = source.find("\n  };", start)
    if end < 0:
        fail("Could not find the end of the English localization map")
    block = source[start:end]
    return set(re.findall(r"^\s*'([a-z0-9_]+)'\s*:", block, re.MULTILINE))


PLACEHOLDER_PATTERN = re.compile(r"%(\d+\$?)?[sd]")


def android_values() -> dict[str, str]:
    root = ET.parse(ANDROID_PATH).getroot()
    return {
        node.attrib["name"]: "".join(node.itertext())
        for node in root.findall("string")
        if "name" in node.attrib
    }


def ios_catalog_keys() -> set[str]:
    catalog = json.loads(IOS_CATALOG_PATH.read_text(encoding="utf-8"))
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        fail("The iOS String Catalog does not contain a strings object")
    return set(strings)


def android_placeholder_errors(
    dart_values: dict[str, str],
    native_values: dict[str, str],
) -> list[str]:
    errors: list[str] = []
    for key in sorted(set(dart_values) & set(native_values)):
        dart_placeholders = sorted(
            value.rstrip("$")
            for value in PLACEHOLDER_PATTERN.findall(dart_values[key])
        )
        android_placeholders = sorted(
            value.rstrip("$")
            for value in PLACEHOLDER_PATTERN.findall(native_values[key])
        )
        if dart_placeholders != android_placeholders:
            errors.append(
                f"Android placeholder mismatch for {key}: "
                f"Dart={dart_placeholders}, Android={android_placeholders}"
            )
    return errors


def dart_values() -> dict[str, str]:
    source = DART_PATH.read_text(encoding="utf-8")
    start = source.find("static const Map<String, String> english")
    if start < 0:
        fail("Could not find the English localization map in app_strings.dart")
    end = source.find("\n  };", start)
    if end < 0:
        fail("Could not find the end of the English localization map")
    block = source[start:end]
    values: dict[str, str] = {}
    for match in re.finditer(
        r"^\s*'([a-z0-9_]+)'\s*:\s*'((?:\\'|[^'])*)'",
        block,
        re.MULTILINE,
    ):
        values[match.group(1)] = match.group(2)
    return values


def describe_difference(
    reference_name: str,
    reference: set[str],
    source_name: str,
    source: set[str],
) -> list[str]:
    messages: list[str] = []
    missing = sorted(reference - source)
    extra = sorted(source - reference)
    if missing:
        messages.append(
            f"{source_name} is missing keys from {reference_name}: "
            + ", ".join(missing)
        )
    if extra:
        messages.append(
            f"{source_name} has extra keys not present in {reference_name}: "
            + ", ".join(extra)
        )
    return messages


def main() -> None:
    required_files = (DART_PATH, ANDROID_PATH, IOS_CATALOG_PATH)
    missing_files = [str(path.relative_to(ROOT)) for path in required_files if not path.exists()]
    if missing_files:
        fail("Missing localization files: " + ", ".join(missing_files))

    dart = dart_keys()
    dart_text = dart_values()
    android_text = android_values()
    android = set(android_text)
    ios = ios_catalog_keys()

    errors = [
        *describe_difference("Dart", dart, "iOS catalog", ios),
    ]

    android_extra = sorted(android - dart)
    if android_extra:
        errors.append(
            "Android has user-facing keys not present in Dart: "
            + ", ".join(android_extra)
        )
    errors.extend(
        android_placeholder_errors(dart_text, android_text)
    )
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)

    if not dart:
        fail("No localization keys were found")

    print(
        "Localization sources are synchronized: "
        f"{len(dart)} Dart/iOS English keys; "
        f"{len(android)} Android native keys validated as a Dart-backed subset."
    )


if __name__ == "__main__":
    main()
