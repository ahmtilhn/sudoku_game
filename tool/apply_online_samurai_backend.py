#!/usr/bin/env python3
"""Thread the duel variant through challenges, queue, matches and rooms."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "backend" / "social_worker" / "src" / "index.ts"


def replace_once(old: str, new: str) -> None:
    source = TARGET.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one marker, found {count}: {old!r}")
    TARGET.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    replace_once(
        "  type DuelMode,\n",
        "  type DuelMode,\n  type DuelVariant,\n",
    )
    replace_once(
        "  difficulty: string;\n  status: string;\n",
        "  difficulty: string;\n  variant: string;\n  status: string;\n",
    )
    replace_once(
        "]);\n\nlet cachedFcmAccessToken",
        "]);\n\n"
        "const DUEL_VARIANTS = new Set(['classic', 'samurai']);\n\n"
        "let cachedFcmAccessToken",
    )
    replace_once(
        "  if (!DIFFICULTIES.has(difficulty)) throw new HttpError(400, 'Invalid difficulty.');\n\n"
        "  const [low, high] = orderedPair(current.id, recipient.id);\n",
        "  if (!DIFFICULTIES.has(difficulty)) throw new HttpError(400, 'Invalid difficulty.');\n"
        "  const variant = duelVariant(body.variant);\n\n"
        "  const [low, high] = orderedPair(current.id, recipient.id);\n",
    )
    replace_once(
        "      id, challenger_id, recipient_id, difficulty, status,\n"
        "      created_at, updated_at, expires_at\n"
        "    ) VALUES (?, ?, ?, ?, 'pending', ?, ?, ?)`,\n",
        "      id, challenger_id, recipient_id, difficulty, variant, status,\n"
        "      created_at, updated_at, expires_at\n"
        "    ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?)`,\n",
    )
    replace_once(
        "      difficulty,\n      nowIso,\n",
        "      difficulty,\n      variant,\n      nowIso,\n",
    )
    replace_once(
        "        difficulty,\n        challengerPublicId: current.public_id,\n",
        "        difficulty,\n        variant,\n        challengerPublicId: current.public_id,\n",
    )
    replace_once(
        "  const difficulty = requiredString(body.difficulty, 'difficulty', 4, 16);\n"
        "  if (!DIFFICULTIES.has(difficulty)) throw new HttpError(400, 'Invalid difficulty.');\n"
        "  const now = new Date().toISOString();\n"
        "  const rating = await ratingFor(env, current.id, difficulty);\n",
        "  const difficulty = requiredString(body.difficulty, 'difficulty', 4, 16);\n"
        "  if (!DIFFICULTIES.has(difficulty)) throw new HttpError(400, 'Invalid difficulty.');\n"
        "  const variant = duelVariant(body.variant);\n"
        "  const now = new Date().toISOString();\n"
        "  const rating = await ratingFor(env, current.id, difficulty);\n",
    )
    replace_once(
        "     WHERE q.difficulty = ?\n       AND q.player_id != ?\n",
        "     WHERE q.variant = ?\n       AND q.difficulty = ?\n       AND q.player_id != ?\n",
    )
    replace_once(
        "    .bind(difficulty, current.id, current.id, current.id, current.id, current.id, rating)\n",
        "    .bind(variant, difficulty, current.id, current.id, current.id, current.id, current.id, rating)\n",
    )
    replace_once(
        "      `INSERT INTO ranked_queue (player_id, difficulty, rating, joined_at, updated_at)\n"
        "       VALUES (?, ?, ?, ?, ?)\n"
        "       ON CONFLICT(player_id) DO UPDATE SET\n"
        "         difficulty = excluded.difficulty,\n",
        "      `INSERT INTO ranked_queue (player_id, variant, difficulty, rating, joined_at, updated_at)\n"
        "       VALUES (?, ?, ?, ?, ?, ?)\n"
        "       ON CONFLICT(player_id) DO UPDATE SET\n"
        "         variant = excluded.variant,\n"
        "         difficulty = excluded.difficulty,\n",
    )
    replace_once(
        "      .bind(current.id, difficulty, rating, now, now)\n",
        "      .bind(current.id, variant, difficulty, rating, now, now)\n",
    )
    replace_once(
        "    return reply(env, { status: 'queued', difficulty, rating });\n",
        "    return reply(env, { status: 'queued', variant, difficulty, rating });\n",
    )
    replace_once(
        "    mode: 'ranked',\n    difficulty,\n",
        "    mode: 'ranked',\n    variant,\n    difficulty,\n",
    )
    replace_once(
        "         player_id, difficulty, rating, joined_at, updated_at, room_id, matched_player_id\n"
        "       ) VALUES (?, ?, ?, ?, ?, ?, ?)\n"
        "       ON CONFLICT(player_id) DO UPDATE SET\n"
        "         difficulty = excluded.difficulty,\n",
        "         player_id, variant, difficulty, rating, joined_at, updated_at, room_id, matched_player_id\n"
        "       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)\n"
        "       ON CONFLICT(player_id) DO UPDATE SET\n"
        "         variant = excluded.variant,\n"
        "         difficulty = excluded.difficulty,\n",
    )
    replace_once(
        "    ).bind(current.id, difficulty, rating, now, now, roomId, opponent.player_id),\n",
        "    ).bind(current.id, variant, difficulty, rating, now, now, roomId, opponent.player_id),\n",
    )
    replace_once(
        "  return reply(env, { status: 'matched', difficulty, roomId }, 201);\n",
        "  return reply(env, { status: 'matched', variant, difficulty, roomId }, 201);\n",
    )
    replace_once(
        "    mode: 'friendly',\n    difficulty: challenge.difficulty,\n",
        "    mode: 'friendly',\n"
        "    variant: duelVariant(challenge.variant),\n"
        "    difficulty: challenge.difficulty,\n",
    )
    replace_once(
        "    mode: DuelMode;\n    difficulty: string;\n",
        "    mode: DuelMode;\n    variant: DuelVariant;\n    difficulty: string;\n",
    )
    replace_once(
        "      id, room_id, challenge_id, mode, difficulty, status,\n"
        "      player_a_id, player_b_id, created_at, updated_at\n"
        "    ) VALUES (?, ?, ?, ?, ?, 'waiting', ?, ?, ?, ?)\n",
        "      id, room_id, challenge_id, mode, variant, difficulty, status,\n"
        "      player_a_id, player_b_id, created_at, updated_at\n"
        "    ) VALUES (?, ?, ?, ?, ?, ?, 'waiting', ?, ?, ?, ?)\n",
    )
    replace_once(
        "      input.mode,\n      input.difficulty,\n",
        "      input.mode,\n      input.variant,\n      input.difficulty,\n",
    )
    replace_once(
        "    mode: row.mode,\n    difficulty: row.difficulty,\n",
        "    mode: row.mode,\n    variant: row.variant ?? 'classic',\n    difficulty: row.difficulty,\n",
    )
    replace_once(
        "    id: challenge.id,\n    difficulty: challenge.difficulty,\n",
        "    id: challenge.id,\n    variant: challenge.variant || 'classic',\n    difficulty: challenge.difficulty,\n",
    )
    replace_once(
        "      mode: match.mode as DuelMode,\n      difficulty: match.difficulty as DuelDifficulty,\n",
        "      mode: match.mode as DuelMode,\n"
        "      variant: duelVariant(match.variant),\n"
        "      difficulty: match.difficulty as DuelDifficulty,\n",
    )
    replace_once(
        "function stringOrNull(value: unknown): string | null {\n",
        "function duelVariant(value: unknown): DuelVariant {\n"
        "  const variant = stringOrNull(value) ?? 'classic';\n"
        "  if (!DUEL_VARIANTS.has(variant)) {\n"
        "    throw new HttpError(400, 'Invalid duel variant.');\n"
        "  }\n"
        "  return variant as DuelVariant;\n"
        "}\n\n"
        "function stringOrNull(value: unknown): string | null {\n",
    )
    print("Online Samurai backend variant integrated.")


if __name__ == "__main__":
    main()
