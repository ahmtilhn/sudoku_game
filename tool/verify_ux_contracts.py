#!/usr/bin/env python3
"""Verify that critical user-facing UX contracts remain wired to production routes."""

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


def require_any(relative: str, needles: tuple[str, ...]) -> None:
    source = read(relative)
    if not any(needle in source for needle in needles):
        raise ContractFailure(
            f"{relative}: expected one of {', '.join(repr(value) for value in needles)}"
        )


def main() -> int:
    try:
        require(
            "lib/app.dart",
            "MainExperienceShell(store: store)",
            "PushRoomNavigationGate",
        )
        require(
            "lib/features/home/main_experience_shell.dart",
            "fantasy-16-launcher",
            "FantasySudokuCatalog.puzzleForSeed",
            "EnhancedGameScreen",
        )
        require(
            "lib/data/fantasy_sudoku_catalog.dart",
            "size: 16",
            "boxRows: 4",
            "boxColumns: 4",
        )
        require(
            "lib/features/game/enhanced_game_screen.dart",
            "action-pause",
            "PopScope<EnhancedGameExit>",
            "_PauseAction.resume",
            "_PauseAction.restart",
            "_PauseAction.menu",
            "InteractiveViewer",
            "UxOutcomeSheet",
        )
        require(
            "lib/features/career/career_screen.dart",
            "EnhancedGameScreen(",
            "mistakeLimit: 3",
            "_showCareerRewardOffer",
        )
        forbid("lib/features/career/career_screen.dart", "GameScreen(")
        require(
            "lib/features/daily/daily_screen.dart",
            "EnhancedGameScreen(",
            "showNextAction: false",
            "today_puzzle_completed",
        )
        forbid("lib/features/daily/daily_screen.dart", "GameScreen(")
        require(
            "lib/widgets/sudoku_board.dart",
            "scheme.onPrimaryContainer",
            "sudokuSymbol(value)",
            "selectedValue",
            "sameValue",
        )
        require(
            "lib/widgets/number_pad.dart",
            "_LargeNumberGrid",
            "sudokuSymbol(value)",
            "NumberPadDock",
        )
        require(
            "lib/services/player_profile_service.dart",
            "ValueNotifier<PlayerProfilePreferences?> current",
            "preferences.profileConfirmed && preferences.nameSource == 'custom'",
            "ensureProfile(displayName: platformName)",
        )
        require(
            "lib/features/social/profile_hub_screen.dart",
            "_games.localPlayer.addListener",
            "_preferencesService.current.addListener",
            "UxCopy.overview(context)",
            "UxCopy.performance(context)",
            "_AchievementSection",
        )
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
            "class UxMetricTile",
            "class UxOutcomeHeader",
            "class UxOutcomeSheet",
        )
        require(
            "lib/features/duel/online_duel_screen.dart",
            "UxOutcomeHeader(",
            "_ResultPlayersRow(",
            "_ResultEloBar(",
        )

        safe_network_screens = (
            "lib/features/duel/leaderboards_screen.dart",
            "lib/features/duel/matchmaking_screen.dart",
            "lib/features/duel/online_duel_screen.dart",
            "lib/features/duel/pre_match_ready_screen.dart",
            "lib/features/economy/wallet_history_screen.dart",
            "lib/features/social/friend_requests_screen.dart",
            "lib/features/social/profile_hub_screen.dart",
            "lib/features/social/social_hub_screen.dart",
            "lib/features/social/challenge_invitation_screen.dart",
            "lib/features/social/challenge_waiting_screen.dart",
            "lib/features/social/platform_services_screen.dart",
            "lib/features/social/platform_social_screen.dart",
        )
        for relative in safe_network_screens:
            require_any(relative, ("UserSafeError.message", "_safeErrorMessage"))

        common_state_screens = (
            "lib/features/duel/leaderboards_screen.dart",
            "lib/features/economy/wallet_history_screen.dart",
            "lib/features/social/friend_requests_screen.dart",
            "lib/features/social/profile_hub_screen.dart",
        )
        for relative in common_state_screens:
            require(relative, "UxStatePanel")

        common_outcome_screens = (
            "lib/features/game/enhanced_game_screen.dart",
            "lib/features/duel/duel_screen.dart",
        )
        for relative in common_outcome_screens:
            require(relative, "UxOutcomeSheet")

        require(
            "test/fantasy_sudoku_test.dart",
            "fantasy puzzle is a valid unique 16x16 Sudoku",
            "_countSolutions",
        )
        require(
            "test/gameplay_ux_test.dart",
            "selected user value uses readable white foreground",
            "pause stops interaction",
        )
        require(
            "test/responsive_feedback_ux_test.dart",
            "shared outcome remains scrollable at 320px and 2x text",
            "16x16 number pad remains usable on a compact phone",
        )
    except ContractFailure as error:
        print(f"UX contract verification failed: {error}")
        return 1

    print("Gameplay, profile, safe-message, route, and common-feedback UX contracts are wired.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
