#!/usr/bin/env python3
"""Verify durable production UX contracts.

The generated UX audit, analyzer and widget tests cover detailed screen behavior.
This gate intentionally checks only stable route, settings, legal and error-safety
contracts so normal UI/artwork refactors do not block CI with stale literals.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ContractFailure(Exception):
    pass


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise ContractFailure(f"missing required source: {relative}")
    return path.read_text(encoding="utf-8")


def require(relative: str, *needles: str) -> None:
    source = read(relative)
    for needle in needles:
        if needle not in source:
            raise ContractFailure(f"{relative}: missing UX contract {needle!r}")


def forbid(relative: str, *needles: str) -> None:
    source = read(relative)
    for needle in needles:
        if needle in source:
            raise ContractFailure(f"{relative}: forbidden legacy UX contract {needle!r}")


def forbid_file(relative: str) -> None:
    if (ROOT / relative).exists():
        raise ContractFailure(f"legacy UX source must stay removed: {relative}")


def main() -> int:
    try:
        # Production route chain.
        require("lib/app.dart", "ChallengeNavigationGate(store: widget.store)")
        require(
            "lib/features/social/challenge_navigation_gate.dart",
            "PlayerIdentityGate(store: widget.store)",
        )
        require(
            "lib/features/social/player_identity_gate.dart",
            "MainExperienceShell(store: widget.store)",
        )
        require(
            "lib/features/home/main_experience_shell.dart",
            "ProfessionalHomeScreen(store: store)",
        )

        # Settings information architecture and release-critical controls.
        settings = "lib/features/settings/ux_settings_screen.dart"
        require(
            settings,
            "AppBackdrop(",
            "LayoutBuilder(",
            "context.tr('play')",
            "context.tr('notifications')",
            "context.tr('privacy')",
            "context.tr('data')",
            "context.tr('clear_career_progress')",
            "context.tr('delete_player_account')",
            "SettingsStrings.privacyPolicyTitle(context)",
            "ads.privacyOptionsRequired",
            "launchUrl(",
            "LaunchMode.externalApplication",
        )
        forbid(
            settings,
            "AccountProtectionScreen",
            "WalletHistoryScreen",
            "context.tr('protect_player_account')",
        )
        forbid_file("lib/features/settings/account_protection_screen.dart")
        forbid_file("lib/features/settings/service_diagnostics_screen.dart")

        require(
            "lib/localization/settings_strings.dart",
            "privacyPolicyTitle",
            "privacyPolicySubtitle",
            "'tr': 'Gizlilik politikası'",
        )
        require(
            "lib/services/account_deletion_service.dart",
            "PlayGamesAuthProvider.PROVIDER_ID",
            "_reauthenticatePlayGames",
            "restorePlayGames: false",
            "v1/me/delete",
        )
        require(
            "lib/data/local_progress_store.dart",
            "Future<void> clearProgress() async",
            "_preferences.remove(_progressKey)",
            "_preferences.remove(_legacyProgressKey)",
        )
        require(
            "lib/features/economy/coin_store_screen.dart",
            "WalletHistoryScreen",
            "restorePurchases",
        )
        require(
            "test/settings_screen_test.dart",
            "legacy account protection is removed and data controls remain",
            "privacy section exposes the privacy policy",
            "find.text(strings.text('coin_history')), findsNothing",
        )

        # User-facing network errors must continue to use the safe mapper.
        require(
            "lib/core/user_safe_error.dart",
            "class UserSafeError",
            "UxCopy.connectionError",
            "UxCopy.accountError",
            "UxCopy.serverBusy",
        )
    except ContractFailure as error:
        print(f"UX contract verification failed: {error}")
        return 1

    print(
        "Production routing, settings/legal controls, destructive-data scope, "
        "and user-safe error contracts are wired."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
