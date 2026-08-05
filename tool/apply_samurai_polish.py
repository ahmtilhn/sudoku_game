#!/usr/bin/env python3
"""Apply final Samurai UX and local-session ownership fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "lib" / "widgets" / "samurai_board.dart"
SAMURAI_SCREEN = ROOT / "lib" / "features" / "game" / "samurai_game_screen.dart"
CLASSIC_SCREEN = ROOT / "lib" / "features" / "game" / "enhanced_game_screen.dart"


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise RuntimeError(
            f"Expected exactly one marker in {path}: {old!r}; found {count}"
        )
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def patch_board() -> None:
    replace_once(
        BOARD,
        "    this.minimumBoardExtent = 630,\n",
        "    this.minimumBoardExtent = 280,\n",
    )


def patch_classic_screen() -> None:
    replace_once(
        CLASSIC_SCREEN,
        "import '../../data/local_progress_store.dart';\n",
        "import '../../data/local_progress_store.dart';\n"
        "import '../../data/samurai_game_session_store.dart';\n",
    )
    replace_once(
        CLASSIC_SCREEN,
        "    WidgetsBinding.instance.addObserver(this);\n"
        "    _board = List<int>.from(widget.puzzle.puzzle);\n",
        "    WidgetsBinding.instance.addObserver(this);\n"
        "    unawaited(SamuraiGameSessionStore.instance.clear());\n"
        "    _board = List<int>.from(widget.puzzle.puzzle);\n",
    )


def patch_samurai_screen() -> None:
    replace_once(
        SAMURAI_SCREEN,
        "import '../../data/local_progress_store.dart';\n",
        "import '../../data/game_session_store.dart';\n"
        "import '../../data/local_progress_store.dart';\n",
    )
    replace_once(
        SAMURAI_SCREEN,
        "import '../../data/samurai_game_session_store.dart';\n",
        "import '../../data/samurai_game_session_store.dart';\n"
        "import '../../data/ux_game_session_store.dart';\n",
    )
    replace_once(
        SAMURAI_SCREEN,
        "    WidgetsBinding.instance.addObserver(this);\n"
        "    final restored = widget.initialSession;\n",
        "    WidgetsBinding.instance.addObserver(this);\n"
        "    unawaited(UxGameSessionStore.instance.clear());\n"
        "    unawaited(GameSessionStore.instance.clearAll());\n"
        "    final restored = widget.initialSession;\n",
    )


def main() -> None:
    patch_board()
    patch_classic_screen()
    patch_samurai_screen()
    print("Samurai polish applied.")


if __name__ == "__main__":
    main()
