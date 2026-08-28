#!/usr/bin/env python3
"""Prevent technical/internal failures from reaching user-facing Flutter UI.

This migration is intentionally conservative and idempotent. Raw exception
messages remain available to logs/Crashlytics and service diagnostics, while
presentation state is routed through UserSafeError. Known gameplay/business
states continue to use their existing localized copy.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FEATURES = ROOT / "lib" / "features"
SAFE_IMPORT = "import '../../core/user_safe_error.dart';"


def ensure_safe_import(source: str) -> str:
    if SAFE_IMPORT in source:
        return source
    anchor = "import 'package:flutter/material.dart';"
    if anchor not in source:
        raise RuntimeError("Could not locate Flutter material import for safe error import")
    return source.replace(anchor, f"{anchor}\n\n{SAFE_IMPORT}", 1)


def write_if_changed(path: Path, source: str, original: str) -> bool:
    if source == original:
        return False
    path.write_text(source, encoding="utf-8")
    return True


def harden_feature_error_state() -> list[str]:
    changed: list[str] = []
    replacements = (
        ("_error = error.message", "_error = UserSafeError.message(context, error)"),
        ("_error = error.toString()", "_error = UserSafeError.message(context, error)"),
        (
            "_statusMessage = error.message",
            "_statusMessage = UserSafeError.message(context, error)",
        ),
        (
            "_statusMessage = error.toString()",
            "_statusMessage = UserSafeError.message(context, error)",
        ),
        ("errorText = error.message", "errorText = UserSafeError.message(context, error)"),
        (
            "errorText = error.toString()",
            "errorText = UserSafeError.message(context, error)",
        ),
        (
            "_snack(error.message)",
            "_snack(UserSafeError.message(context, error))",
        ),
        (
            "_snack(error.toString())",
            "_snack(UserSafeError.message(context, error))",
        ),
        (
            "Text(error.message)",
            "Text(UserSafeError.message(context, error))",
        ),
        (
            "Text(error.toString())",
            "Text(UserSafeError.message(context, error))",
        ),
    )

    for path in sorted(FEATURES.rglob("*.dart")):
        original = path.read_text(encoding="utf-8")
        source = original
        touched = False
        for old, new in replacements:
            if old in source:
                source = source.replace(old, new)
                touched = True
        if "fallback: error.message," in source:
            source = source.replace("fallback: error.message,\n", "")
            touched = True
        if touched:
            source = ensure_safe_import(source)
            if write_if_changed(path, source, original):
                changed.append(str(path.relative_to(ROOT)))
    return changed


def harden_challenge_navigation() -> list[str]:
    path = ROOT / "lib/features/social/challenge_navigation_gate.dart"
    original = path.read_text(encoding="utf-8")
    source = original
    unsafe = """      final message = error.statusCode == 404 || error.statusCode == 409
          ? context.tr('challenge_timed_out')
          : error.message;"""
    safe = """      final message = error.statusCode == 404 || error.statusCode == 409
          ? context.tr('challenge_timed_out')
          : UserSafeError.message(context, error);"""
    if unsafe in source:
        source = source.replace(unsafe, safe, 1)
        source = ensure_safe_import(source)
    return [str(path.relative_to(ROOT))] if write_if_changed(path, source, original) else []


def harden_profile_business_errors() -> list[str]:
    path = ROOT / "lib/features/social/player_identity_gate.dart"
    original = path.read_text(encoding="utf-8")
    source = original
    # Do not trust every HTTP 400/409 body. Client-side validation already
    # handles normal form rules; unexpected server text must stay internal.
    unsafe = """    if (error is PlayerProfileException &&
        (error.statusCode == 400 || error.statusCode == 409)) {
      return error.message;
    }
    if (error is SocialApiException &&
        (error.statusCode == 400 || error.statusCode == 409)) {
      return error.message;
    }
"""
    safe = """    if (error is PlayerProfileException && error.code == 'username_taken') {
      return context.tr('try_again');
    }
    if (error is SocialApiException && error.statusCode == 409) {
      return context.tr('try_again');
    }
"""
    if unsafe in source:
        source = source.replace(unsafe, safe, 1)
    return [str(path.relative_to(ROOT))] if write_if_changed(path, source, original) else []


def harden_push_service() -> list[str]:
    path = ROOT / "lib/services/push_notification_service.dart"
    original = path.read_text(encoding="utf-8")
    source = original

    class_anchor = """  static const String _challengeChannelId = 'online_challenges';
  static const String _enabledKey = 'challenge_push_enabled_v1';"""
    class_replacement = """  static const String _challengeChannelId = 'online_challenges';
  static const String _enabledKey = 'challenge_push_enabled_v1';
  static const String _safeRegistrationError =
      'Notification setup could not be completed. Please try again.';"""
    if "_safeRegistrationError" not in source and class_anchor in source:
        source = source.replace(class_anchor, class_replacement, 1)

    source = source.replace(
        "lastRegistrationError.value = error.toString();",
        "lastRegistrationError.value = _safeRegistrationError;",
    )
    source = source.replace(
        "lastRegistrationError.value = error.message;",
        "lastRegistrationError.value = _safeRegistrationError;",
    )
    source = source.replace(
        "lastRegistrationError.value = 'FCM registration token is unavailable.';",
        "lastRegistrationError.value = _safeRegistrationError;",
    )

    # Foreground notifications are derived from a validated app-owned type.
    # Never render an arbitrary remote notification title/body directly.
    source = source.replace(
        "await _showForegroundSystemNotification(message, target);",
        "await _showForegroundSystemNotification(target);",
    )
    source = source.replace(
        """  Future<void> _showForegroundSystemNotification(
    RemoteMessage message,
    PushNotificationDestination target,
  ) async {""",
        """  Future<void> _showForegroundSystemNotification(
    PushNotificationDestination target,
  ) async {""",
    )
    source = source.replace(
        "title: message.notification?.title ?? target.defaultTitle,",
        "title: target.defaultTitle,",
    )
    source = source.replace(
        "body: message.notification?.body ?? target.defaultBody,",
        "body: target.defaultBody,",
    )

    return [str(path.relative_to(ROOT))] if write_if_changed(path, source, original) else []


def strengthen_guard() -> list[str]:
    path = ROOT / "tool/verify_user_facing_messages.py"
    original = path.read_text(encoding="utf-8")
    source = original

    if "ADDITIONAL_RAW_RENDER_PATTERNS" not in source:
        marker = "\nFORBIDDEN_LITERAL_TERMS = ("
        addition = r'''

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
'''
        if marker not in source:
            raise RuntimeError("Could not extend user-facing error verifier")
        source = source.replace(marker, addition + marker, 1)

    source = source.replace(
        "for label, pattern in RAW_RENDER_PATTERNS:",
        "for label, pattern in RAW_RENDER_PATTERNS + ADDITIONAL_RAW_RENDER_PATTERNS:",
    )

    if "push_source =" not in source:
        marker = "\n    if violations:\n"
        addition = '''
    push_path = ROOT / "lib" / "services" / "push_notification_service.dart"
    push_source = without_line_comments(push_path.read_text(encoding="utf-8"))
    for label, pattern in PUSH_SERVICE_PATTERNS:
        for match in pattern.finditer(push_source):
            line = push_source.count("\\n", 0, match.start()) + 1
            excerpt = " ".join(match.group(0).split())[:180]
            violations.append(f"{push_path.relative_to(ROOT)}:{line}: {label}: {excerpt}")
'''
        if marker not in source:
            raise RuntimeError("Could not add push-service error checks")
        source = source.replace(marker, addition + marker, 1)

    return [str(path.relative_to(ROOT))] if write_if_changed(path, source, original) else []


def verify_postconditions() -> None:
    forbidden = {
        "lib/features/social/challenge_navigation_gate.dart": (": error.message;",),
        "lib/features/social/platform_services_screen.dart": ("fallback: error.message",),
        "lib/services/push_notification_service.dart": (
            "lastRegistrationError.value = error.toString()",
            "lastRegistrationError.value = error.message",
            "message.notification?.title",
            "message.notification?.body",
        ),
    }
    violations: list[str] = []
    for relative, snippets in forbidden.items():
        text = (ROOT / relative).read_text(encoding="utf-8")
        for snippet in snippets:
            if snippet in text:
                violations.append(f"{relative}: {snippet}")

    for path in sorted(FEATURES.rglob("*.dart")):
        text = path.read_text(encoding="utf-8")
        for pattern in (
            r"\b(?:_error|errorText|_statusMessage)\s*=\s*error\.message\b",
            r"\b(?:_error|errorText|_statusMessage)\s*=\s*error\.toString\(\)",
            r"\bfallback\s*:\s*error\.message\b",
            r"\breturn\s+error\.message\s*;",
            r"\b_snack\s*\(\s*error\.(?:message|toString\(\))",
            r"\bText\s*\(\s*error\.(?:message|toString\(\))",
        ):
            if re.search(pattern, text):
                violations.append(str(path.relative_to(ROOT)))
                break

    if violations:
        raise RuntimeError(
            "Technical error hardening incomplete:\n- " + "\n- ".join(sorted(set(violations)))
        )


def main() -> int:
    changed: list[str] = []
    changed.extend(harden_feature_error_state())
    changed.extend(harden_challenge_navigation())
    changed.extend(harden_profile_business_errors())
    changed.extend(harden_push_service())
    changed.extend(strengthen_guard())
    verify_postconditions()

    unique = sorted(set(changed))
    print(f"Hardened user-facing error handling in {len(unique)} file(s).")
    for path in unique:
        print(f"- {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
