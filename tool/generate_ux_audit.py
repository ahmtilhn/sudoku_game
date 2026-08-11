#!/usr/bin/env python3
"""Generate a deterministic UX audit for every production screen."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "ux_audit.md"
SCREEN_GLOB = "*_screen.dart"

RESPONSIVE_MARKERS = (
    "LayoutBuilder",
    "ConstrainedBox",
    "Wrap(",
    "GridView",
    "ListView",
    "SingleChildScrollView",
    "CustomScrollView",
    "TabBarView",
    "InteractiveViewer",
    "Responsive",
)
SCROLL_MARKERS = (
    "ListView",
    "SingleChildScrollView",
    "CustomScrollView",
    "GridView",
    "TabBarView",
    "InteractiveViewer",
)
STATE_MARKERS = (
    "UxStatePanel",
    "CircularProgressIndicator",
    "LinearProgressIndicator",
    "FutureBuilder",
    "StreamBuilder",
    "RefreshIndicator",
)
REMOTE_MARKERS = (
    "ApiClient",
    "SocialApiClient",
    "EconomyApiClient",
    "PlatformGameServices",
    "Firebase",
    "http.",
    "WebSocket",
)
OUTCOME_MARKERS = (
    "UxOutcomeSheet",
    "UxOutcomeHeader",
    "_finishGame(",
    "_showLossSheet(",
    "OnlineDuelResult",
    "you_won",
    "you_lost",
    "round_lost",
    "player_won",
    "winner ==",
)


def yes(value: bool) -> str:
    return "Yes" if value else "—"


def is_forwarding_wrapper(source: str, classes: list[str]) -> bool:
    if len(classes) != 1:
        return False
    build_match = re.search(
        r"Widget\s+build\s*\([^)]*\)\s*(?:=>|\{\s*return)\s*(?:const\s+)?(\w+Screen)\s*\(",
        source,
        re.DOTALL,
    )
    return build_match is not None and build_match.group(1) != classes[0]


def classify(path: Path) -> dict[str, str]:
    source = path.read_text(encoding="utf-8")
    classes = re.findall(r"class\s+(\w*Screen)\b", source)
    relative = path.relative_to(ROOT).as_posix()
    feature = path.relative_to(ROOT / "lib" / "features").parts[0]
    wrapper = is_forwarding_wrapper(source, classes)
    remote = any(marker in source for marker in REMOTE_MARKERS)
    catches = "catch (" in source or "catch(" in source
    safe_error = "UserSafeError" in source or "_safeErrorMessage" in source
    common_state = "UxStatePanel" in source
    common_outcome = "UxOutcome" in source or "UxOutcomeHeader" in source
    outcome_related = any(marker in source for marker in OUTCOME_MARKERS)
    responsive = wrapper or any(marker in source for marker in RESPONSIVE_MARKERS)
    scrollable = wrapper or any(marker in source for marker in SCROLL_MARKERS)
    state_feedback = wrapper or any(marker in source for marker in STATE_MARKERS)
    localized = wrapper or any(
        marker in source
        for marker in ("context.tr(", "context.strings", "_accountText(")
    )
    safe_area = wrapper or "SafeArea" in source or "AppBackdrop" in source

    findings: list[str] = []
    if remote and catches and not safe_error:
        findings.append("Remote failure path needs user-safe mapping review")
    if not wrapper and not responsive:
        findings.append("No explicit responsive primitive detected")
    if not wrapper and not scrollable and source.count("Column(") >= 2:
        findings.append("Dense column without explicit scroll marker")
    if outcome_related and not common_outcome:
        findings.append("Outcome content does not use shared outcome component")
    if not localized:
        findings.append("No localization call detected")

    role = "Forwarding wrapper" if wrapper else "Production screen"
    return {
        "path": relative,
        "feature": feature,
        "classes": ", ".join(classes) if classes else path.stem,
        "role": role,
        "safe_area": yes(safe_area),
        "responsive": yes(responsive),
        "scroll": yes(scrollable),
        "state": yes(state_feedback),
        "safe_error": yes(safe_error or not (remote and catches)),
        "common_state": yes(common_state or wrapper),
        "common_outcome": yes(common_outcome or not outcome_related or wrapper),
        "localized": yes(localized),
        "findings": "; ".join(findings) if findings else "No static warning",
    }


def render(rows: list[dict[str, str]]) -> str:
    warnings = [row for row in rows if row["findings"] != "No static warning"]
    features = sorted({row["feature"] for row in rows})
    wrappers = sum(row["role"] == "Forwarding wrapper" for row in rows)
    lines: list[str] = [
        "# Complete UX Audit",
        "",
        "This report inventories every production `*_screen.dart` file under `lib/features`. It combines source-level UX checks with the gameplay, profile, feedback, localization, error-safety, branch and release work completed on `main`.",
        "",
        "## Audit scope",
        "",
        f"- Screen files: **{len(rows)}**",
        f"- Forwarding/compatibility wrappers: **{wrappers}**",
        f"- Feature groups: **{len(features)}** ({', '.join(features)})",
        "- Required device behavior: compact phone, large phone/tablet, text scaling, safe insets, keyboard insets and scroll recovery",
        "- Required state behavior: loading, empty, recoverable error, disabled/busy and completed/outcome",
        "- Required message behavior: no raw exception, HTTP code, Firebase/backend/OAuth/SHA/configuration text in production UI",
        "",
        "## High-impact findings fixed",
        "",
        "1. **Sudoku cell visibility:** selected user values now use a white high-contrast foreground and shadow; selected, related, matching, fixed, hinted and error states have distinct colors.",
        "2. **Pause flow:** explicit pause button, stopped timer, hidden board, disabled controls, continue/restart/main-menu actions, restart confirmation and back-button interception.",
        "3. **16×16 Fantasy:** valid unique 4×4-box puzzle, 1–9/A–G symbols, responsive number grid, zoom/pan, persistence and a visible main-experience launcher.",
        "4. **Google Play identity:** live player name/avatar refresh, first-profile creation and protection of a confirmed custom nickname.",
        "5. **Profile hierarchy:** identity header, platform status, ELO/rank/peak/country, W-L-D/win rate/streak/tournament data, achievements and separate account/social actions.",
        "6. **Technical error exposure:** central `UserSafeError`, static CI guard and user-safe network/account/server messages across online, social, wallet, settings and platform flows.",
        "7. **Shared feedback system:** `UxStatePanel`, `UxMetricTile`, `UxOutcomeHeader` and `UxOutcomeSheet` now define loading/empty/error/result presentation.",
        "8. **Outcome consistency:** career/practice/daily completion, loss/continue, local duel and online duel share the same outcome header and information hierarchy.",
        "9. **Gameplay route consistency:** career and daily modes now open `EnhancedGameScreen`; compatibility wrappers are reported separately instead of being treated as broken screens.",
        "10. **Release safety:** localization, user-safe messages, UX contracts, fatal analyzer, tests, debug APK and release AAB are CI gates.",
        "",
        "## Screen inventory",
        "",
        "| Feature | Screen / file | Role | Safe area | Responsive | Scroll | State feedback | Safe errors | Shared state | Shared outcome | Localized | Static finding |",
        "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for row in rows:
        lines.append(
            "| {feature} | `{classes}`<br>`{path}` | {role} | {safe_area} | {responsive} | {scroll} | {state} | {safe_error} | {common_state} | {common_outcome} | {localized} | {findings} |".format(**row)
        )

    lines.extend(
        [
            "",
            "## Static warnings requiring visual regression attention",
            "",
        ]
    )
    if not warnings:
        lines.append("No source-level warnings remain.")
    else:
        for row in warnings:
            lines.append(f"- `{row['path']}`: {row['findings']}")

    lines.extend(
        [
            "",
            "Static warnings are not automatically defects. Confirmation dialogs, short setup screens and game canvases may intentionally omit a list or common state panel. They remain listed so visual/device tests do not silently skip them.",
            "",
            "## Interaction and accessibility rules",
            "",
            "- Primary controls use at least 44–48 logical pixels and remain reachable under text scaling.",
            "- Destructive restart/account actions require confirmation.",
            "- Long and data-driven screens use scrollable content and refresh/retry recovery.",
            "- Result sheets expose a single primary action, optional secondary action and lower-emphasis exit action.",
            "- Loading and error regions use semantic live regions; Sudoku cells expose row, column, value and selected state.",
            "- Platform identity is advisory: it may initialize a profile but cannot overwrite a confirmed custom nickname.",
            "- 16×16 is offline/special mode and does not silently affect online rating or career progression.",
            "",
            "## Verification gates",
            "",
            "- `python3 tool/validate_localizations.py`",
            "- `python3 tool/verify_user_facing_messages.py`",
            "- `python3 tool/verify_ux_contracts.py`",
            "- `python3 tool/generate_ux_audit.py --check`",
            "- `flutter analyze --fatal-infos`",
            "- `flutter test --concurrency=1`",
            "- `flutter build apk --debug`",
            "- `flutter build appbundle --release`",
            "- `tool/verify_android_release_config.ps1`",
            "- `tool/verify_online_aab.ps1`",
            "",
            "## Manual release smoke matrix",
            "",
            "1. Install from Google Play internal testing, not by sideloading the local APK.",
            "2. Confirm Play Games consent, automatic avatar/name and preserved custom nickname.",
            "3. Enter a number into a selected cell in normal and high-contrast modes.",
            "4. Pause for at least ten seconds; confirm time does not advance and the board is hidden.",
            "5. Restart and return to menu; confirm save/confirmation behavior.",
            "6. Open 16×16, enter A–G values, add notes, zoom, background the app and resume.",
            "7. Exercise offline/server-down states for profile, friends, leaderboard, wallet and matchmaking; verify no technical text appears.",
            "8. Complete and lose career/practice/daily/local duel/online duel sessions; compare visual hierarchy and action order.",
            "9. Test 320×568, 360×800, 412×915 and tablet widths with text scale 1.0, 1.3 and 2.0.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    paths = sorted((ROOT / "lib" / "features").rglob(SCREEN_GLOB))
    rows = [classify(path) for path in paths]
    content = render(rows)

    if args.write:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(content, encoding="utf-8")
        print(f"Wrote {OUTPUT.relative_to(ROOT)} with {len(rows)} screen files.")
        return 0

    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != content:
            print("UX audit is stale. Run: python3 tool/generate_ux_audit.py --write")
            return 1
        print(f"UX audit is current for {len(rows)} screen files.")
        return 0

    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
