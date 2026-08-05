#!/usr/bin/env python3
"""Add a backward-compatible classic/samurai variant to the duel state."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "backend" / "social_worker" / "src" / "online_duel.ts"


def replace_once(old: str, new: str) -> None:
    source = TARGET.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one marker, found {count}: {old!r}")
    TARGET.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    replace_once(
        "export type DuelMode = 'friendly' | 'ranked';\n",
        "export type DuelMode = 'friendly' | 'ranked';\n"
        "export type DuelVariant = 'classic' | 'samurai';\n",
    )
    replace_once(
        "  mode: DuelMode;\n  difficulty: DuelDifficulty;\n",
        "  mode: DuelMode;\n"
        "  variant?: DuelVariant;\n"
        "  difficulty: DuelDifficulty;\n",
    )
    replace_once(
        "  mode: DuelMode;\n  difficulty: DuelDifficulty;\n  playerA: PlayerPublic;\n",
        "  mode: DuelMode;\n"
        "  variant?: DuelVariant;\n"
        "  difficulty: DuelDifficulty;\n"
        "  playerA: PlayerPublic;\n",
    )
    replace_once(
        "  const generated = rankedPuzzle(input.difficulty, input.randomBytes);\n",
        "  const variant = input.variant ?? 'classic';\n"
        "  const generated = rankedPuzzle(input.difficulty, input.randomBytes, variant);\n",
    )
    replace_once(
        "    mode: input.mode,\n    difficulty: input.difficulty,\n",
        "    mode: input.mode,\n"
        "    variant,\n"
        "    difficulty: input.difficulty,\n",
    )
    replace_once(
        "  if (!Number.isInteger(cellIndex) || cellIndex < 0 || cellIndex >= 81) {\n",
        "  if (\n"
        "    !Number.isInteger(cellIndex) ||\n"
        "    cellIndex < 0 ||\n"
        "    cellIndex >= state.puzzle.length\n"
        "  ) {\n",
    )
    replace_once(
        "    now >= state.startedAt + MAX_MATCH_DURATION_MS\n",
        "    now >= state.startedAt + matchDurationMs(state)\n",
    )
    replace_once(
        "    mode: state.mode,\n    difficulty: state.difficulty,\n",
        "    mode: state.mode,\n"
        "    variant: state.variant ?? 'classic',\n"
        "    difficulty: state.difficulty,\n",
    )
    replace_once(
        "      state.startedAt === null ? null : state.startedAt + MAX_MATCH_DURATION_MS,\n",
        "      state.startedAt === null ? null : state.startedAt + matchDurationMs(state),\n",
    )
    replace_once(
        "function rankedPuzzle(difficulty: DuelDifficulty, randomBytes: Uint8Array): {\n",
        "function rankedPuzzle(\n"
        "  difficulty: DuelDifficulty,\n"
        "  randomBytes: Uint8Array,\n"
        "  variant: DuelVariant,\n"
        "): {\n",
    )
    replace_once(
        "  const selected = selectRankedPuzzle(difficulty, randomBytes);\n",
        "  const selected = selectRankedPuzzle(difficulty, randomBytes, variant);\n",
    )
    source = TARGET.read_text(encoding="utf-8")
    marker = "function rankedPuzzle(\n"
    helper = (
        "function matchDurationMs(state: DuelState): number {\n"
        "  return (state.variant ?? 'classic') === 'samurai'\n"
        "    ? 60 * 60 * 1_000\n"
        "    : MAX_MATCH_DURATION_MS;\n"
        "}\n\n"
    )
    if helper not in source:
        count = source.count(marker)
        if count != 1:
            raise RuntimeError(f"Expected rankedPuzzle marker once, found {count}")
        TARGET.write_text(source.replace(marker, helper + marker, 1), encoding="utf-8")
    print("Online duel Samurai core integrated.")


if __name__ == "__main__":
    main()
