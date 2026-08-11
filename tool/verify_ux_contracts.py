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
            "ProfessionalHomeScreen(store: store)",
        )
        require(
            "lib/features/home/professional_home_screen.dart",
            "DuelAsset.homePlayScene",
            "DuelAsset.homeDuelScene",
            "DuelAsset.gift",
            "DuelAsset.coin",
            "DuelAsset.leaderboardCrownPro",
            "LeaderboardsScreen",
            "constraints: const BoxConstraints(maxWidth: 760)",
            "home-logo-text",
            "assets/images/ui/logo_text.png",
            "errorBuilder:",
            "allowNotes: true",
            "SudokuVariant.values",
            "SudokuVariantId.classic16",
            "Classic16PuzzleFactory.generate",
            "NeverScrollableScrollPhysics",
            "GameModal.error",
        )
        require(
            "lib/domain/classic16_puzzle_factory.dart",
            "size = 16",
            "boxSize = 4",
            "List<int>.generate(size",
        )
        require(
            "lib/features/game/enhanced_game_screen.dart",
            "action-pause",
            "PopScope<EnhancedGameExit>",
            "_PauseAction.resume",
            "_PauseAction.restart",
            "_PauseAction.menu",
            "showDialog<_PauseAction>",
            "GamePauseMenu(",
            "InteractiveViewer",
            "classic16-board-viewport",
            "16×16 · 1–16",
            "_fitBoard",
            "_notes.putIfAbsent",
            "_notes.remove(index)",
            "UxOutcomeSheet",
        )
        forbid(
            "lib/features/game/enhanced_game_screen.dart",
            "16×16 · A–G",
            "showAdaptiveBottomSheet<_PauseAction>",
        )
        require(
            "lib/widgets/game_pause_menu.dart",
            "class GamePauseMenu",
            "game-pause-menu",
            "pause-resume",
            "pause-restart",
            "pause-menu",
        )
        require(
            "lib/features/career/career_hub_screen.dart",
            "SudokuVariant.values",
            "nextCareerLevelNumberFor",
            "Classic16PuzzleFactory.generate",
            "NeverScrollableScrollPhysics",
            "GameModal.error",
        )
        require(
            "lib/features/duel/matchmaking_screen.dart",
            "VariantMatchmakingClient.instance",
            "SudokuVariant.values",
            "DuelAsset.board16Pro",
            "DuelAsset.coin",
            "alignment: Alignment.topCenter",
            "WrapAlignment.center",
            "context.tr('entry_fee')",
            "context.tr('winner_pot')",
            "Classic16PuzzleFactory.generate",
            "allowNotes: true",
            "GameModal.error",
            "LayoutBuilder(",
            "Expanded(",
        )
        forbid(
            "lib/features/duel/matchmaking_screen.dart",
            "SingleChildScrollView",
            "ListView",
            "GridView",
        )
        require(
            "lib/features/social/social_hub_screen.dart",
            "SudokuVariant.values",
            "variant: selection.variant",
            "DuelAsset.board16Pro",
            "GameModal.error",
        )
        require(
            "lib/features/social/challenge_waiting_screen.dart",
            "challenge.variant.label",
            "DuelAsset.board16Pro",
            "GameModal.error",
        )
        require(
            "lib/features/social/ux_challenge_invitation_screen.dart",
            "challenge.variant.label",
            "DuelAsset.board16Pro",
            "GameModal.warning",
            "GameModal.error",
        )
        require(
            "lib/services/social_api_client.dart",
            "SudokuVariant variant = SudokuVariant.classic9",
            "'variant': variant.key",
            "final SudokuVariant variant",
            "boardSize",
            "cellCount",
        )
        require(
            "backend/social_worker/src/entry_v2.ts",
            "handleVariantMatchmakingRequest",
            "handleVariantChallengeRequest",
        )
        require(
            "backend/social_worker/src/variant_challenges.ts",
            "classic16:",
            "board_size",
            "cell_count",
            "augmentChallenge",
        )
        require(
            "lib/features/career/career_screen.dart",
            "EnhancedGameScreen(",
            "mistakeLimit: 3",
            "_showCareerRewardOffer",
        )
        forbid(
            "lib/features/career/career_screen.dart",
            "import '../game/game_screen.dart';",
            "=> GameScreen(",
        )
        require(
            "lib/features/daily/daily_screen.dart",
            "EnhancedGameScreen(",
            "showNextAction: false",
            "today_puzzle_completed",
        )
        forbid(
            "lib/features/daily/daily_screen.dart",
            "import '../game/game_screen.dart';",
            "=> GameScreen(",
        )
        require(
            "lib/widgets/sudoku_board.dart",
            "scheme.onPrimaryContainer",
            "sudokuSymbol(value)",
            "selectedValue",
            "sameValue",
            "_NotesCell(",
        )
        require(
            "lib/widgets/number_pad.dart",
            "_LargeNumberGrid",
            "sudokuSymbol(value)",
            "NumberPadDock",
            "action-erase",
            "action-notes",
            "unlimitedHints",
        )
        require(
            "lib/debug/debug_economy.dart",
            "debugUnlimitedHintBalance",
            "debugUnlimitedHintsEnabled",
            "SUDOKU_DISABLE_DEBUG_UNLIMITED_HINTS",
        )
        require(
            "lib/data/local_progress_store.dart",
            "final bool unlimitedHints",
            "if (unlimitedHints) return true",
            "hints = debugUnlimitedHintBalance",
        )
        require(
            "lib/widgets/duel_asset_icon.dart",
            "SvgPicture.asset",
            "static const board9Pro",
            "static const board16Pro",
            "static const statusErrorPro",
            "static const homePlayScene",
            "static const resultVictoryTrophyPro",
            "static const leaderboardCrownPro",
            "static const Set<String> fullColorArtwork",
        )
        require(
            "lib/features/economy/coin_store_screen.dart",
            "DuelAsset.coinStoreBalancePro",
            "DuelAsset.gift",
            "DuelAsset.removeAdsPro",
            "DuelAsset.diamond",
            "_StoreArtwork",
        )
        forbid(
            "lib/features/economy/coin_store_screen.dart",
            "width: 360",
        )
        require(
            "lib/widgets/game_modal.dart",
            "enum GameModalTone",
            "class GameModal",
            "DuelAsset.statusErrorPro",
            "DuelAsset.statusSuccessPro",
            "DuelAsset.statusWarningPro",
            "DuelAsset.statusOfflinePro",
        )
        require(
            "lib/services/player_profile_service.dart",
            "ValueNotifier<PlayerProfilePreferences?> current",
            "PlatformProfilePolicy.decideNameUpdate",
            "profileConfirmed: preferences.profileConfirmed",
            "currentNameSource: preferences.nameSource",
            "platformDisplayName: platformName",
            "ensureProfile(displayName: platformName)",
        )
        require(
            "lib/features/social/profile_hub_screen.dart",
            "_games.localPlayer.addListener",
            "_preferencesService.current.addListener",
            "localAvatarBytes: avatarBytes",
            "UxCopy.overview(context)",
            "UxCopy.performance(context)",
            "LeaderboardsScreen",
            "_AchievementBadge",
            "NeverScrollableScrollPhysics",
            "GameModal.error",
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
            "DuelAsset.resultVictoryTrophyPro",
            "DuelAsset.resultDefeatTrophyPro",
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
            "lib/features/social/ux_challenge_invitation_screen.dart",
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
            "test/classic16_puzzle_factory_test.dart",
            "generates a valid numeric 16x16 puzzle",
            "contains(16)",
        )
        require(
            "test/gameplay_ux_test.dart",
            "selected user value uses readable white foreground",
            "notes render inside the selected cell and erase clears them",
            "pause stops interaction",
        )
        require(
            "test/debug_unlimited_hints_test.dart",
            "unlimited hint inventory never decrements",
            "normal hint inventory still decrements",
        )
        require(
            "test/game_pause_menu_test.dart",
            "pause menu fits a compact phone without overflow",
            "game-pause-menu",
            "16×16 · 1–16",
        )
        require(
            "test/responsive_feedback_ux_test.dart",
            "shared outcome remains scrollable at 320px and 2x text",
            "16x16 number pad remains usable on a compact phone",
        )
    except ContractFailure as error:
        print(f"UX contract verification failed: {error}")
        return 1

    print("Professional home, logo, aligned play/duel cards, notes, debug hints, variant, game, social, profile, safe-message, and common-feedback UX contracts are wired.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
