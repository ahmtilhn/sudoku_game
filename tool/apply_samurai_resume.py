#!/usr/bin/env python3
"""Apply the final mounted guards to Samurai outcome flows."""

from pathlib import Path

SCREEN = (
    Path(__file__).resolve().parents[1]
    / "lib"
    / "features"
    / "game"
    / "samurai_game_screen.dart"
)


def replace_once(old: str, new: str) -> None:
    source = SCREEN.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one marker, found {count}: {old!r}")
    SCREEN.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    replace_once(
        "    await _persistNow();\n\n"
        "    final action = await showAdaptiveBottomSheet<_SamuraiPauseAction>(\n",
        "    await _persistNow();\n"
        "    if (!mounted) return;\n\n"
        "    final action = await showAdaptiveBottomSheet<_SamuraiPauseAction>(\n",
    )
    replace_once(
        "    await _sessionStore.clear();\n\n"
        "    final action = await showAdaptiveBottomSheet<_SamuraiLossAction>(\n",
        "    await _sessionStore.clear();\n"
        "    if (!mounted) return;\n\n"
        "    final action = await showAdaptiveBottomSheet<_SamuraiLossAction>(\n",
    )
    print("Samurai mounted guards applied.")


if __name__ == "__main__":
    main()
