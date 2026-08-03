from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    (ROOT / path).write_text(value, encoding="utf-8")


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return source.replace(old, new, 1)


def replace_regex(source: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, source, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{label}: expected one regex match, found {count}")
    return updated


# ---------------------------------------------------------------------------
# Challenge HTTP API, room validation, and settlement hardening.
# ---------------------------------------------------------------------------
path = "backend/social_worker/src/index.ts"
source = read(path)
source = replace_once(
    source,
    "import { AppCheckError, verifyAppCheckRequest } from './app_check';\n",
    "import { AppCheckError, verifyAppCheckRequest } from './app_check';\n"
    "import { coinBalance, ensureStarterGrant, entryFeeForDifficulty } from './economy';\n",
    "economy imports",
)

source = replace_once(
    source,
    "      } else if (url.pathname === '/v1/challenges' && request.method === 'GET') {\n"
    "        response = await listChallenges(url, env, player);\n"
    "      } else if (\n"
    "        url.pathname === '/v1/matchmaking/queue' &&\n",
    "      } else if (url.pathname === '/v1/challenges' && request.method === 'GET') {\n"
    "        response = await listChallenges(url, env, player);\n"
    "      } else if (\n"
    "        /^\\/v1\\/challenges\\/[^/]+$/.test(url.pathname) &&\n"
    "        request.method === 'GET'\n"
    "      ) {\n"
    "        response = await getChallenge(env, player, url.pathname.split('/')[3]);\n"
    "      } else if (\n"
    "        /^\\/v1\\/challenges\\/[^/]+$/.test(url.pathname) &&\n"
    "        request.method === 'DELETE'\n"
    "      ) {\n"
    "        response = await cancelChallenge(env, ctx, player, url.pathname.split('/')[3]);\n"
    "      } else if (\n"
    "        url.pathname === '/v1/matchmaking/queue' &&\n",
    "challenge detail routes",
)

new_create = r'''async function createChallenge(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  current: PlayerRow,
): Promise<Response> {
  await enforceRateLimit(env, `challenge:${current.id}`, 10, 600);
  const body = await readJson(request);
  const recipient = await playerByPublicId(
    env,
    requiredString(body.recipientPublicId, 'recipientPublicId', 4, 64),
  );
  if (recipient.id === current.id) throw new HttpError(400, 'You cannot challenge yourself.');
  const difficulty = requiredString(body.difficulty, 'difficulty', 4, 16);
  if (!DIFFICULTIES.has(difficulty)) throw new HttpError(400, 'Invalid difficulty.');

  const [low, high] = orderedPair(current.id, recipient.id);
  const blocked = await env.DB.prepare(
    `SELECT 1 FROM friendships
     WHERE player_low_id = ? AND player_high_id = ? AND status = 'blocked'`,
  )
    .bind(low, high)
    .first();
  if (blocked) throw new HttpError(403, 'This player is unavailable.');

  if (await playerHasActiveMatch(env, current.id)) {
    throw new HttpError(409, 'Finish or cancel your active online match first.');
  }
  if (await playerHasActiveMatch(env, recipient.id)) {
    throw new HttpError(409, 'This player is already in an online match.');
  }

  await Promise.all([
    ensureStarterGrant(env, current.id),
    ensureStarterGrant(env, recipient.id),
  ]);
  const entryFee = entryFeeForDifficulty(difficulty);
  const [senderBalance, recipientBalance] = await Promise.all([
    coinBalance(env, current.id),
    coinBalance(env, recipient.id),
  ]);
  if (senderBalance < entryFee) {
    throw new HttpError(409, `You need at least ${entryFee} Coins to send this challenge.`);
  }
  if (recipientBalance < entryFee) {
    throw new HttpError(409, `This player needs at least ${entryFee} Coins to accept.`);
  }

  const now = new Date();
  const nowIso = now.toISOString();
  await env.DB.prepare(
    `UPDATE challenges SET status = 'expired', updated_at = ?
     WHERE status = 'pending' AND expires_at <= ?`,
  )
    .bind(nowIso, nowIso)
    .run();

  const reversePending = await env.DB.prepare(
    `SELECT id FROM challenges
     WHERE challenger_id = ? AND recipient_id = ? AND status = 'pending'
     LIMIT 1`,
  )
    .bind(recipient.id, current.id)
    .first<{ id: string }>();
  if (reversePending) {
    throw new HttpError(409, 'This player already sent you a pending challenge.');
  }

  const id = crypto.randomUUID();
  const expires = new Date(now.getTime() + 15 * 60 * 1000);
  const inserted = await env.DB.prepare(
    `INSERT OR IGNORE INTO challenges (
      id, challenger_id, recipient_id, difficulty, status,
      created_at, updated_at, expires_at
    ) VALUES (?, ?, ?, ?, 'pending', ?, ?, ?)`,
  )
    .bind(
      id,
      current.id,
      recipient.id,
      difficulty,
      nowIso,
      nowIso,
      expires.toISOString(),
    )
    .run();

  if ((inserted.meta.changes ?? 0) === 0) {
    const existing = await env.DB.prepare(
      `SELECT * FROM challenges
       WHERE challenger_id = ? AND recipient_id = ? AND status = 'pending'
       ORDER BY created_at DESC LIMIT 1`,
    )
      .bind(current.id, recipient.id)
      .first<ChallengeRow>();
    if (!existing) throw new HttpError(409, 'A challenge is already pending.');
    return reply(env, await challengeJson(env, existing));
  }

  ctx.waitUntil(
    sendPlayerNotification(env, recipient.id, {
      title: 'New Sudoku challenge',
      body: `${current.display_name} challenged you on ${difficulty}.`,
      data: {
        type: 'challenge',
        challengeId: id,
        difficulty,
        challengerPublicId: current.public_id,
      },
    }),
  );

  const created = await challengeById(env, id);
  return reply(env, await challengeJson(env, created), 201);
}

async function listChallenges'''
source = replace_regex(
    source,
    r"async function createChallenge\([\s\S]*?\n}\n\nasync function listChallenges",
    new_create,
    "create challenge",
)

insert_after_list = r'''async function getChallenge(
  env: Env,
  current: PlayerRow,
  challengeId: string,
): Promise<Response> {
  const challenge = await challengeById(env, challengeId);
  if (
    challenge.challenger_id !== current.id &&
    challenge.recipient_id !== current.id
  ) {
    throw new HttpError(403, 'You are not a participant in this challenge.');
  }
  if (
    challenge.status === 'pending' &&
    Date.parse(challenge.expires_at) <= Date.now()
  ) {
    await env.DB.prepare(
      `UPDATE challenges SET status = 'expired', updated_at = ?
       WHERE id = ? AND status = 'pending'`,
    )
      .bind(new Date().toISOString(), challenge.id)
      .run();
  }
  return reply(env, await challengeJson(env, await challengeById(env, challenge.id)));
}

async function cancelChallenge(
  env: Env,
  ctx: ExecutionContext,
  current: PlayerRow,
  challengeId: string,
): Promise<Response> {
  const challenge = await challengeById(env, challengeId);
  if (challenge.challenger_id !== current.id) {
    throw new HttpError(403, 'Only the challenger can cancel this invitation.');
  }
  if (challenge.status === 'cancelled') {
    return reply(env, await challengeJson(env, challenge));
  }
  if (challenge.status !== 'pending') {
    throw new HttpError(409, 'This challenge can no longer be cancelled.');
  }
  const now = new Date().toISOString();
  const updated = await env.DB.prepare(
    `UPDATE challenges SET status = 'cancelled', room_id = NULL, updated_at = ?
     WHERE id = ? AND status = 'pending'`,
  )
    .bind(now, challenge.id)
    .run();
  if ((updated.meta.changes ?? 0) > 0) {
    ctx.waitUntil(
      sendPlayerNotification(env, challenge.recipient_id, {
        title: 'Challenge cancelled',
        body: `${current.display_name} cancelled the Sudoku challenge.`,
        data: {
          type: 'challenge_response',
          challengeId: challenge.id,
          status: 'cancelled',
          roomId: '',
        },
      }),
    );
  }
  return reply(env, await challengeJson(env, await challengeById(env, challenge.id)));
}

'''
source = replace_once(
    source,
    "async function respondChallenge(\n",
    insert_after_list + "async function respondChallenge(\n",
    "challenge detail functions",
)

new_respond = r'''async function respondChallenge(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  current: PlayerRow,
  challengeId: string,
): Promise<Response> {
  const body = await readJson(request);
  const action = requiredString(body.action, 'action', 4, 16);
  if (action !== 'accept' && action !== 'decline') {
    throw new HttpError(400, 'Challenge action must be accept or decline.');
  }

  let challenge = await challengeById(env, challengeId);
  if (challenge.recipient_id !== current.id) {
    throw new HttpError(403, 'Only the recipient can respond.');
  }

  if (action === 'decline') {
    if (challenge.status === 'declined') {
      return reply(env, await challengeJson(env, challenge));
    }
    if (challenge.status !== 'pending') {
      throw new HttpError(409, 'Challenge is no longer pending.');
    }
    if (Date.parse(challenge.expires_at) <= Date.now()) {
      await env.DB.prepare(
        `UPDATE challenges SET status = 'expired', updated_at = ? WHERE id = ?`,
      )
        .bind(new Date().toISOString(), challenge.id)
        .run();
      throw new HttpError(409, 'Challenge expired.');
    }

    const updated = await env.DB.prepare(
      `UPDATE challenges SET status = 'declined', room_id = NULL, updated_at = ?
       WHERE id = ? AND status = 'pending'`,
    )
      .bind(new Date().toISOString(), challenge.id)
      .run();
    challenge = await challengeById(env, challenge.id);
    if ((updated.meta.changes ?? 0) === 0) {
      if (challenge.status === 'declined') {
        return reply(env, await challengeJson(env, challenge));
      }
      throw new HttpError(409, 'Challenge response was already completed.');
    }
    ctx.waitUntil(
      sendPlayerNotification(env, challenge.challenger_id, {
        title: 'Challenge declined',
        body: `${current.display_name} declined your Sudoku challenge.`,
        data: {
          type: 'challenge_response',
          challengeId: challenge.id,
          status: 'declined',
          roomId: '',
        },
      }),
    );
    return reply(env, await challengeJson(env, challenge));
  }

  if (challenge.status === 'accepted') {
    const roomId = await ensureAcceptedChallengeMatch(env, challenge);
    const currentChallenge = await challengeById(env, challenge.id);
    return reply(env, {
      ...(await challengeJson(env, currentChallenge)),
      roomId,
    });
  }
  if (challenge.status !== 'pending') {
    throw new HttpError(409, 'Challenge is no longer available.');
  }
  if (Date.parse(challenge.expires_at) <= Date.now()) {
    await env.DB.prepare(
      `UPDATE challenges SET status = 'expired', updated_at = ? WHERE id = ?`,
    )
      .bind(new Date().toISOString(), challenge.id)
      .run();
    throw new HttpError(409, 'Challenge expired.');
  }

  if (await playerHasActiveMatch(env, challenge.challenger_id)) {
    throw new HttpError(409, 'The challenger is already in an online match.');
  }
  if (await playerHasActiveMatch(env, challenge.recipient_id)) {
    throw new HttpError(409, 'Finish or cancel your active online match first.');
  }

  await Promise.all([
    ensureStarterGrant(env, challenge.challenger_id),
    ensureStarterGrant(env, challenge.recipient_id),
  ]);
  const entryFee = entryFeeForDifficulty(challenge.difficulty);
  const [challengerBalance, recipientBalance] = await Promise.all([
    coinBalance(env, challenge.challenger_id),
    coinBalance(env, challenge.recipient_id),
  ]);
  if (challengerBalance < entryFee || recipientBalance < entryFee) {
    await env.DB.prepare(
      `UPDATE challenges SET status = 'cancelled', room_id = NULL, updated_at = ?
       WHERE id = ? AND status = 'pending'`,
    )
      .bind(new Date().toISOString(), challenge.id)
      .run();
    throw new HttpError(409, `Both players need at least ${entryFee} Coins.`);
  }

  const candidateRoomId = challenge.room_id || crypto.randomUUID();
  const transitioned = await env.DB.prepare(
    `UPDATE challenges SET status = 'accepted', room_id = ?, updated_at = ?
     WHERE id = ? AND status = 'pending'`,
  )
    .bind(candidateRoomId, new Date().toISOString(), challenge.id)
    .run();
  challenge = await challengeById(env, challenge.id);
  if (challenge.status !== 'accepted') {
    throw new HttpError(409, 'Challenge response was already completed.');
  }

  const roomId = await ensureAcceptedChallengeMatch(env, challenge);
  if ((transitioned.meta.changes ?? 0) > 0) {
    ctx.waitUntil(
      sendPlayerNotification(env, challenge.challenger_id, {
        title: 'Challenge accepted',
        body: `${current.display_name} accepted your Sudoku challenge.`,
        data: {
          type: 'challenge_response',
          challengeId: challenge.id,
          status: 'accepted',
          roomId,
        },
      }),
    );
  }

  const updated = await challengeById(env, challenge.id);
  return reply(env, await challengeJson(env, updated));
}

async function joinRankedQueue'''
source = replace_regex(
    source,
    r"async function respondChallenge\([\s\S]*?\n}\n\nasync function joinRankedQueue",
    new_respond,
    "respond challenge",
)

new_active = r'''async function activeMatch(env: Env, current: PlayerRow): Promise<Response> {
  let match = await activeMatchForPlayer(env, current.id);

  if (!match) {
    const acceptedChallenge = await env.DB.prepare(
      `SELECT * FROM challenges
       WHERE (challenger_id = ? OR recipient_id = ?)
         AND status = 'accepted'
       ORDER BY updated_at DESC
       LIMIT 1`,
    )
      .bind(current.id, current.id)
      .first<ChallengeRow>();
    if (acceptedChallenge) {
      try {
        const roomId = await ensureAcceptedChallengeMatch(env, acceptedChallenge);
        match = await env.DB.prepare(
          `SELECT * FROM matches WHERE room_id = ? LIMIT 1`,
        )
          .bind(roomId)
          .first<Record<string, unknown>>();
      } catch (error) {
        if (!(error instanceof HttpError) || error.status >= 500) throw error;
      }
    }
  }

  return reply(env, { match: match ? publicMatch(match, current.id) : null });
}

async function activeMatchForPlayer(
  env: Env,
  playerId: string,
): Promise<Record<string, unknown> | null> {
  return env.DB.prepare(
    `SELECT * FROM matches
     WHERE (player_a_id = ? OR player_b_id = ?)
       AND status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')
     ORDER BY created_at DESC
     LIMIT 1`,
  )
    .bind(playerId, playerId)
    .first<Record<string, unknown>>();
}

async function playerHasActiveMatch(env: Env, playerId: string): Promise<boolean> {
  return (await activeMatchForPlayer(env, playerId)) !== null;
}

async function matchHistory'''
source = replace_regex(
    source,
    r"async function activeMatch\([\s\S]*?\n}\n\nasync function matchHistory",
    new_active,
    "active match",
)

new_ensure = r'''async function ensureAcceptedChallengeMatch(
  env: Env,
  challenge: ChallengeRow,
): Promise<string> {
  const existing = await env.DB.prepare(
    `SELECT id, room_id, status FROM matches WHERE challenge_id = ? LIMIT 1`,
  )
    .bind(challenge.id)
    .first<{ id: string; room_id: string; status: string }>();
  if (existing?.room_id) {
    const funded = await env.DB.prepare(
      `SELECT status FROM match_coin_escrow WHERE match_id = ? LIMIT 1`,
    )
      .bind(existing.id)
      .first<{ status: string }>();
    if (
      !['waiting', 'ready_window', 'countdown', 'active', 'paused'].includes(existing.status) ||
      funded?.status !== 'funded'
    ) {
      await env.DB.prepare(
        `UPDATE challenges SET status = 'cancelled', room_id = NULL, updated_at = ?
         WHERE id = ? AND status = 'accepted'`,
      )
        .bind(new Date().toISOString(), challenge.id)
        .run();
      throw new HttpError(409, 'The accepted challenge room is no longer playable.');
    }
    if (challenge.room_id !== existing.room_id || challenge.status !== 'accepted') {
      await env.DB.prepare(
        `UPDATE challenges SET status = 'accepted', room_id = ?, updated_at = ? WHERE id = ?`,
      )
        .bind(existing.room_id, new Date().toISOString(), challenge.id)
        .run();
    }
    return existing.room_id;
  }

  const roomId = challenge.room_id || crypto.randomUUID();
  const now = new Date().toISOString();
  await createMatchRow(env, {
    roomId,
    challengeId: challenge.id,
    mode: 'friendly',
    difficulty: challenge.difficulty,
    playerAId: challenge.challenger_id,
    playerBId: challenge.recipient_id,
    now,
  });

  const created = await env.DB.prepare(
    `SELECT id, room_id, status FROM matches
     WHERE challenge_id = ? OR room_id = ?
     ORDER BY CASE WHEN challenge_id = ? THEN 0 ELSE 1 END
     LIMIT 1`,
  )
    .bind(challenge.id, roomId, challenge.id)
    .first<{ id: string; room_id: string; status: string }>();
  const funded = created
    ? await env.DB.prepare(
        `SELECT status FROM match_coin_escrow WHERE match_id = ? LIMIT 1`,
      )
        .bind(created.id)
        .first<{ status: string }>()
    : null;
  if (!created?.room_id || created.status !== 'waiting' || funded?.status !== 'funded') {
    await env.DB.prepare(
      `UPDATE challenges SET status = 'cancelled', room_id = NULL, updated_at = ?
       WHERE id = ?`,
    )
      .bind(now, challenge.id)
      .run();
    throw new HttpError(409, 'Both players need enough Coin to create the challenge room.');
  }

  await env.DB.prepare(
    `UPDATE challenges SET status = 'accepted', room_id = ?, updated_at = ? WHERE id = ?`,
  )
    .bind(created.room_id, now, challenge.id)
    .run();
  return created.room_id;
}

async function createMatchRow'''
source = replace_regex(
    source,
    r"async function ensureAcceptedChallengeMatch\([\s\S]*?\n}\n\nasync function createMatchRow",
    new_ensure,
    "ensure accepted room",
)

source = replace_once(
    source,
    "    mode: row.mode,\n    difficulty: row.difficulty,\n",
    "    mode: row.mode,\n    difficulty: row.difficulty,\n    challengeId: row.challenge_id ?? null,\n",
    "public match challenge id",
)

source = replace_once(
    source,
    "    `SELECT * FROM matches\n     WHERE room_id = ? LIMIT 1`,\n",
    "    `SELECT * FROM matches\n     WHERE room_id = ?\n       AND status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')\n     LIMIT 1`,\n",
    "connect active status",
)

source = replace_once(
    source,
    "  private roomState: DuelState | null = null;\n",
    "  private roomState: DuelState | null = null;\n  private persistedMatchStatus: string | null = null;\n",
    "room persisted status field",
)

source = replace_once(
    source,
    "       WHERE m.room_id = ?\n       LIMIT 1`,\n",
    "       WHERE m.room_id = ?\n         AND m.status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')\n       LIMIT 1`,\n",
    "room load active status",
)

source = replace_once(
    source,
    "  private async persist(): Promise<void> {\n    if (!this.roomState) return;\n    await this.state.storage.put('duelState', this.roomState);\n    await this.scheduleAlarm();\n  }\n",
    "  private async persist(): Promise<void> {\n    if (!this.roomState) return;\n    await this.state.storage.put('duelState', this.roomState);\n    const activeStatuses = new Set(['waiting', 'ready_window', 'countdown', 'active', 'paused']);\n    if (\n      activeStatuses.has(this.roomState.status) &&\n      this.persistedMatchStatus !== this.roomState.status\n    ) {\n      await this.env.DB.prepare(\n        `UPDATE matches SET status = ?, updated_at = ? WHERE id = ?`,\n      )\n        .bind(this.roomState.status, new Date().toISOString(), this.roomState.matchId)\n        .run();\n      this.persistedMatchStatus = this.roomState.status;\n    }\n    await this.scheduleAlarm();\n  }\n",
    "persist match status",
)

source = replace_once(
    source,
    "        status: duel.status,\n        readyDeadline: duel.readyDeadline,\n",
    "        status: duel.status,\n        lobbyDeadline: duel.lobbyDeadline ?? null,\n        readyDeadline: duel.readyDeadline,\n",
    "schedule lobby deadline",
)

recent_statement = """      this.env.DB.prepare(\n        `INSERT INTO recent_opponents (\n           player_low_id, player_high_id, last_challenge_id, last_winner_id, last_played_at\n         ) VALUES (?, ?, ?, ?, ?)\n         ON CONFLICT(player_low_id, player_high_id) DO UPDATE SET\n           last_challenge_id = excluded.last_challenge_id,\n           last_winner_id = excluded.last_winner_id,\n           last_played_at = excluded.last_played_at`,\n      ).bind(\n        ...orderedPair(duel.playerA.player.id, duel.playerB.player.id),\n        duel.challengeId,\n        winnerId,\n        now,\n      ),\n"""
source = replace_once(
    source,
    "      this.matchPlayerStatement(duel, 'A', resultA, duel.ratingResult.A, now),\n      this.matchPlayerStatement(duel, 'B', resultB, duel.ratingResult.B, now),\n",
    "      this.matchPlayerStatement(duel, 'A', resultA, duel.ratingResult.A, now),\n      this.matchPlayerStatement(duel, 'B', resultB, duel.ratingResult.B, now),\n" + recent_statement,
    "recent opponents settlement",
)
write(path, source)

# ---------------------------------------------------------------------------
# Authoritative duel lobby expiry and terminal settlement visibility.
# ---------------------------------------------------------------------------
path = "backend/social_worker/src/online_duel.ts"
source = read(path)
source = replace_once(
    source,
    "export const READY_DEADLINE_MS = READY_WINDOW_SECONDS * 1_000;\n",
    "export const READY_DEADLINE_MS = READY_WINDOW_SECONDS * 1_000;\n"
    "export const LOBBY_DEADLINE_MS = 2 * 60 * 1_000;\n",
    "lobby constant",
)
source = replace_once(
    source,
    "  readyDeadline: number | null;\n",
    "  lobbyDeadline?: number | null;\n  readyDeadline: number | null;\n",
    "lobby field",
)
source = replace_once(
    source,
    "    readyDeadline: null,\n    startedAt: null,\n",
    "    lobbyDeadline: input.now + LOBBY_DEADLINE_MS,\n    readyDeadline: null,\n    startedAt: null,\n",
    "initial lobby deadline",
)
source = replace_once(
    source,
    "export function applyDueDeadlines(state: DuelState, now: number): PublicEvent[] {\n  const events: PublicEvent[] = [];\n",
    "export function applyDueDeadlines(state: DuelState, now: number): PublicEvent[] {\n  const events: PublicEvent[] = [];\n"
    "  const lobbyDeadline = state.lobbyDeadline ?? (state.createdAt + LOBBY_DEADLINE_MS);\n"
    "  state.lobbyDeadline = lobbyDeadline;\n"
    "  if (\n"
    "    state.status === 'waiting' &&\n"
    "    state.startedAt === null &&\n"
    "    now >= lobbyDeadline\n"
    "  ) {\n"
    "    state.status = 'cancelled';\n"
    "    state.finishedAt = now;\n"
    "    state.winnerSeat = null;\n"
    "    state.finishReason = 'lobby_timeout';\n"
    "    state.revision++;\n"
    "    events.push(event(state, 'match_completed', now, publicResult(state)));\n"
    "    return events;\n"
    "  }\n",
    "lobby timeout",
)
source = replace_once(
    source,
    "    readyDeadline: state.readyDeadline,\n    matchDeadline:\n",
    "    lobbyDeadline: state.lobbyDeadline ?? null,\n    readyDeadline: state.readyDeadline,\n    matchDeadline:\n",
    "snapshot lobby deadline",
)
source = replace_once(
    source,
    "    rating: state.status === 'completed' || state.status === 'forfeited'\n      ? state.ratingResult\n      : null,\n    coinSettlement: state.status === 'completed' || state.status === 'forfeited'\n      ? state.coinResult\n      : null,\n",
    "    rating: state.settled && isTerminalStatus(state.status)\n      ? state.ratingResult\n      : null,\n    coinSettlement: state.settled && isTerminalStatus(state.status)\n      ? state.coinResult\n      : null,\n",
    "terminal settlement snapshot",
)
source = replace_once(
    source,
    "  state.status = 'ready_window';\n  state.readyDeadline = now + READY_DEADLINE_MS;\n",
    "  state.status = 'ready_window';\n  state.lobbyDeadline = null;\n  state.readyDeadline = now + READY_DEADLINE_MS;\n",
    "open ready window",
)
source = replace_once(
    source,
    "  state.status = 'active';\n  state.startedAt = now;\n",
    "  state.status = 'active';\n  state.lobbyDeadline = null;\n  state.startedAt = now;\n",
    "clear lobby on start",
)
source = replace_once(
    source,
    "function publicResult(state: DuelState): Record<string, unknown> {\n",
    "function isTerminalStatus(status: MatchStatus): boolean {\n"
    "  return status === 'completed' || status === 'forfeited' || status === 'cancelled' || status === 'abandoned';\n"
    "}\n\nfunction publicResult(state: DuelState): Record<string, unknown> {\n",
    "terminal helper",
)
write(path, source)

# Alarm scheduling includes the lobby deadline.
path = "backend/social_worker/src/cost_retention.ts"
source = read(path)
source = replace_once(
    source,
    "    status: string;\n    readyDeadline: number | null;\n",
    "    status: string;\n    lobbyDeadline?: number | null;\n    readyDeadline: number | null;\n",
    "alarm lobby input",
)
source = replace_once(
    source,
    "  const deadlines = [\n    input.status === 'ready_window' ? input.readyDeadline : null,\n",
    "  const deadlines = [\n    input.status === 'waiting' ? input.lobbyDeadline ?? null : null,\n    input.status === 'ready_window' ? input.readyDeadline : null,\n",
    "alarm lobby deadline",
)
write(path, source)

# Runtime schema: one pending challenge per direction and variable entry-fee invariant.
path = "backend/social_worker/src/runtime_schema.ts"
source = read(path)
source = replace_once(
    source,
    "const RUNTIME_TRIGGER_SCHEMA_VERSION = 1;\n",
    "const RUNTIME_TRIGGER_SCHEMA_VERSION = 2;\n",
    "runtime schema version",
)
source = replace_once(
    source,
    "  if (current?.version === RUNTIME_TRIGGER_SCHEMA_VERSION) return;\n\n  for (const name of RUNTIME_TRIGGER_NAMES) {\n",
    "  if (current?.version === RUNTIME_TRIGGER_SCHEMA_VERSION) return;\n\n"
    "  await env.DB.prepare(\n"
    "    `UPDATE challenges SET status = 'cancelled', updated_at = ?\n"
    "     WHERE status = 'pending'\n"
    "       AND rowid NOT IN (\n"
    "         SELECT MAX(rowid) FROM challenges\n"
    "         WHERE status = 'pending'\n"
    "         GROUP BY challenger_id, recipient_id\n"
    "       )`,\n"
    "  )\n"
    "    .bind(new Date().toISOString())\n"
    "    .run();\n"
    "  await env.DB.prepare(\n"
    "    `CREATE UNIQUE INDEX IF NOT EXISTS challenges_unique_pending_direction_idx\n"
    "     ON challenges(challenger_id, recipient_id)\n"
    "     WHERE status = 'pending'`,\n"
    "  ).run();\n\n"
    "  for (const name of RUNTIME_TRIGGER_NAMES) {\n",
    "pending challenge index",
)
source = replace_regex(
    source,
    r"  `CREATE TRIGGER IF NOT EXISTS validate_match_entry_ledger_before_insert[\s\S]*?   END`,",
    """  `CREATE TRIGGER IF NOT EXISTS validate_match_entry_ledger_before_insert
   BEFORE INSERT ON coin_ledger
   WHEN NEW.reason = 'match_entry'
     AND NEW.amount < 0
     AND NEW.balance_after != (
       SELECT online_coins FROM players WHERE id = NEW.player_id
     )
   BEGIN
     SELECT RAISE(ABORT, 'match_entry_balance_invariant');
   END`,""",
    "variable entry invariant",
)
write(path, source)

# Both websocket entry paths reject terminal DB matches.
path = "backend/social_worker/src/main.ts"
source = read(path)
source = replace_once(
    source,
    "      `SELECT player_a_id, player_b_id\n       FROM matches\n       WHERE room_id = ?\n       LIMIT 1`,\n",
    "      `SELECT player_a_id, player_b_id, status\n       FROM matches\n       WHERE room_id = ?\n         AND status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')\n       LIMIT 1`,\n",
    "main websocket active match",
)
source = replace_once(
    source,
    ".first<{ player_a_id: string; player_b_id: string }>();\n",
    ".first<{ player_a_id: string; player_b_id: string; status: string }>();\n",
    "main websocket match type",
)
write(path, source)

# Migration documents and applies the pending-direction invariant remotely.
migration = ROOT / "backend/social_worker/migrations/0016_challenge_hardening.sql"
migration.write_text(
    """-- Challenge lifecycle hardening.\n"
    "UPDATE challenges\n"
    "SET status = 'cancelled', updated_at = datetime('now')\n"
    "WHERE status = 'pending'\n"
    "  AND rowid NOT IN (\n"
    "    SELECT MAX(rowid)\n"
    "    FROM challenges\n"
    "    WHERE status = 'pending'\n"
    "    GROUP BY challenger_id, recipient_id\n"
    "  );\n\n"
    "CREATE UNIQUE INDEX IF NOT EXISTS challenges_unique_pending_direction_idx\n"
    "  ON challenges(challenger_id, recipient_id)\n"
    "  WHERE status = 'pending';\n"
    """,
    encoding="utf-8",
)

# Backend regression tests lock the new invariants and lobby lifecycle.
path = "backend/social_worker/test/online_duel.test.ts"
source = read(path)
source = replace_once(
    source,
    "  MAX_CONSECUTIVE_TIMEOUTS,\n",
    "  LOBBY_DEADLINE_MS,\n  MAX_CONSECUTIVE_TIMEOUTS,\n",
    "test lobby import",
)
source = replace_once(
    source,
    "  it('settles explicit forfeit with the opponent as winner', () => {\n",
    "  it('cancels and refunds a room forfeited before the match starts', () => {\n"
    "    const duel = state();\n\n"
    "    applyForfeit(duel, 'A', 'cancel-before-start', 1_003);\n\n"
    "    expect(duel.status).toBe('cancelled');\n"
    "    expect(duel.winnerSeat).toBeNull();\n"
    "    expect(duel.finishReason).toBe('cancelled_before_start');\n"
    "  });\n\n"
    "  it('cancels an abandoned lobby after the server deadline', () => {\n"
    "    const duel = state();\n\n"
    "    const events = applyDueDeadlines(duel, duel.createdAt + LOBBY_DEADLINE_MS);\n\n"
    "    expect(duel.status).toBe('cancelled');\n"
    "    expect(duel.finishReason).toBe('lobby_timeout');\n"
    "    expect(events.map((event) => event.type)).toContain('match_completed');\n"
    "  });\n\n"
    "  it('settles explicit forfeit with the opponent as winner', () => {\n",
    "lobby and prestart tests",
)
write(path, source)

(ROOT / "backend/social_worker/test/challenge_hardening.test.ts").write_text(
    """import { readFileSync } from 'node:fs';\n"
    "import { describe, expect, it } from 'vitest';\n\n"
    "const indexSource = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');\n"
    "const runtimeSource = readFileSync(new URL('../src/runtime_schema.ts', import.meta.url), 'utf8');\n"
    "const mainSource = readFileSync(new URL('../src/main.ts', import.meta.url), 'utf8');\n\n"
    "describe('challenge lifecycle hardening', () => {\n"
    "  it('exposes exact status and challenger cancellation routes', () => {\n"
    "    expect(indexSource).toContain('async function getChallenge');\n"
    "    expect(indexSource).toContain('async function cancelChallenge');\n"
    "    expect(indexSource).toContain(\"request.method === 'DELETE'\");\n"
    "  });\n\n"
    "  it('requires funded escrow before returning an accepted room', () => {\n"
    "    expect(indexSource).toContain(\"funded?.status !== 'funded'\");\n"
    "    expect(indexSource).toContain(\"Both players need enough Coin\");\n"
    "  });\n\n"
    "  it('prevents duplicate pending challenges and terminal room replay', () => {\n"
    "    expect(runtimeSource).toContain('challenges_unique_pending_direction_idx');\n"
    "    expect(indexSource).toContain(\"status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')\");\n"
    "    expect(mainSource).toContain(\"status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')\");\n"
    "  });\n\n"
    "  it('records recent opponents during authoritative settlement', () => {\n"
    "    expect(indexSource).toContain('INSERT INTO recent_opponents');\n"
    "    expect(indexSource).toContain('last_winner_id = excluded.last_winner_id');\n"
    "  });\n"
    "});\n"
    """,
    encoding="utf-8",
)

print('Challenge backend hardening applied.')
