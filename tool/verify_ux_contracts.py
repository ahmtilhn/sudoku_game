#!/usr/bin/env python3
"""Verify durable user-facing UX contracts on production routes.

This gate intentionally checks architectural and interaction contracts rather than
individual artwork literals. Visual asset inventory changes frequently and is
covered by the generated UX audit and widget tests; route wiring, destructive
settings, safety surfaces and core gameplay affordances must remain stable.
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


def require_any(relative: str, needles: tuple[str, ...]) -> None:
    source = read(relative)
    if not any(needle in source for needle in needles):
        raise ContractFailure(
            f"{relative}: expected one of {', '.join(repr(value) for value in needles)}"
        )


def main() -> int:
    try:
        # Production route chain. This mirrors the actual app architecture rather
        # than requiring the home shell to be instantiated directly in app.dart.
        require(
            "lib/app.dart",
            "ChallengeNavigationGate(store: widget.store)",
        )
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

        # Settings must keep the current product information architecture: no
        # legacy account-protection surface, no duplicated wallet history, and
        # destructive/legal controls remain directly discoverable.
        require(
            "lib/features/settings/ux_settings_screen.dart",
            "AppBackdrop(",
            "LayoutBuilder(",
            "SingleChildScrollView(",
            "context.tr('play')",
            "context.tr('notifications')",
            "context.tr('privacy')",
            "context.tr('data')",
            "context.tr('clear_career_progress')",
            "context.tr('delete_player_account')",
            "SettingsStrings.privacyPolicyTitle(context)",
            "SettingsStrings.privacyPolicySubtitle(context)",
            "ads.privacyOptionsRequired",
            "launchUrl(",
            "LaunchMode.externalApplication",
        )
        forbid(
            "lib/features/settings/ux_settings_screen.dart",
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

        # Core gameplay UX contracts that should not regress while screen art or
        # copy evolves.
        require(
            "lib/features/game/enhanced_game_screen.dart",
            "GamePauseMenu(",
            "InteractiveViewer",
            "UxOutcomeSheet",
            "action-pause",
            "_notes.putIfAbsent",
            "_notes.remove(index)",
        )
        require(
            "lib/widgets/game_pause_menu.dart",
            "class GamePauseMenu",
            "pause-resume",
            "pause-restart",
            "pause-menu",
        )
        require(
            "lib/widgets/sudoku_board.dart",
            "sudokuSymbol(value)",
            "selectedValue",
            "sameValue",
            "_NotesCell(",
        )
        require(
            "lib/widgets/number_pad.dart",
            "sudokuSymbol(value)",
            "action-erase",
            "action-notes",
        )
        require(
            "lib/features/career/career_screen.dart",
            "EnhancedGameScreen(",
            "mistakeLimit: 3",
        )
        require(
            "lib/features/daily/daily_screen.dart",
            "EnhancedGameScreen(",
            "showNextAction: false",
        )

        # Network-facing production screens must map failures to user-safe copy.
        safe_network_screens = (
            "lib/features/duel/leaderboards_screen.dart",
            "lib/features/duel/matchmaking_screen.dart",
            "lib/features/duel/online_duel_screen.dart",
            "lib/features/economy/wallet_history_screen.dart",
            "lib/features/social/friend_requests_screen.dart",
            "lib/features/social/profile_hub_screen.dart",
            "lib/features/social/social_hub_screen.dart",
            "lib/features/social/challenge_waiting_screen.dart",
            "lib/features/social/ux_challenge_invitation_screen.dart",
        )
        for relative in safe_network_screens:
            require_any(relative, ("UserSafeError.message", "_safeErrorMessage"))

        require(
            "lib/core/user_safe_error.dart",
            "class UserSafeError",
            "UxCopy.connectionError",
            "UxCopy.accountError",
            "UxCopy.serverBusy",
        )
        require(
            "lib/widgets/ux_feedback.dart",
            "class UxStatePanel",
            "class UxOutcomeSheet",
        )

        require(
            "test/gameplay_ux_test.dart",
            "selected user value uses readable white foreground",
            "notes render inside the selected cell and erase clears them",
            "pause stops interaction",
        )
        require(
            "test/game_pause_menu_test.dart",
            "pause menu fits a compact phone without overflow",
            "game-pause-menu",
        )
        require(
            "test/responsive_feedback_ux_test.dart",
            "shared outcome remains scrollable at 320px and 2x text",
            "16x16 number pad remains usable on a compact phone",
        )
    except ContractFailure as error:
        print(f"UX contract verification failed: {error}")
        return 1

    print(
        "Production routing, settings/legal controls, safe network feedback, "
        "and core gameplay UX contracts are wired."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
