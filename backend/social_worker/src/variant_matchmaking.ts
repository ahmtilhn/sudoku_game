import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';
import {
  EconomyError,
  MAX_RATED_PAIR_MATCHES_24H,
  coinBalance,
  createFundedMatch,
  ensureStarterGrant,
  entryFeeForDifficulty,
  type EconomyEnv,
  type FundedMatchInput,
} from './economy';
import {
  MATCHMAKING_UNBOUNDED_RATING_DELTA,
  matchmakingRatingDeltaForWaitMs,
} from './matchmaking_model';
import { LOBBY_DEADLINE_MS } from './online_duel_model';
import { roomIdForVariant } from './online_duel_factory';
import {
  duelVariantConfig,
  normalizeDuelVariant,
  type DuelVariant,
} from './sudoku_variant';
import { ensureVariantSchema } from './variant_schema';

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

const DIFFICULTIES = new Set([
  'beginner',
  'easy',
  'medium',
  'hard',
  'expert',
]);
const ACTIVE_MATCH_STATUSES =
  "'waiting', 'ready_window', 'countdown', 'active', 'paused'";
const QUEUE_STALE_AFTER_MS = 2 * 60 * 1000;
const MATCH_LOBBY_STALE_AFTER_MS = LOBBY_DEADLINE_MS;
const RANKED_PAIR_WINDOW_MS = 24 * 60 * 60 * 1000;
const DIFFICULTY_ORDER = ['beginner', 'easy', 'medium', 'hard', 'expert'];
const MATCHMAKING_5_SECONDS_MS = 5_000;
const MATCHMAKING_10_SECONDS_MS = 10_000;
const MATCHMAKING_15_SECONDS_MS = 15_000;
const MATCHMAKING_20_SECONDS_MS = 20_000;

export type VariantMatchmakingEnv = EconomyEnv & {
  FIREBASE_PROJECT_ID: string;
  ALLOWED_ORIGIN?: string;
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
};

type LegacyFetch = (
  request: Request,
  env: VariantMatchmakingEnv,
  ctx: ExecutionContext,
) => Promise<Response>;

type MatchmakingRequest = {
  playerId: string;
  difficulty: string;
  variant: DuelVariant;
  rating: number;
};

type MatchmakingResult = {
  status: 'queued' | 'matched';
  difficulty: string;
  variant: DuelVariant;
  boardSize: number;
  cellCount: number;
  playerId: string;
  rating?: number;
  roomId?: string;
  onlineCoins?: number;
};

export async function handleVariantMatchmakingRequest(
  request: Request,
  env: VariantMatchmakingEnv,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
): Promise<Response> {
  await ensureVariantSchema(env);

  if (request.method !== 'POST' && request.method !== 'DELETE') {
    return json(env, 405, { error: 'Method not allowed.' });
  }

  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    const playerId = await ensurePlayerId(
      request,
      env,
      ctx,
      uid,
      legacyFetch,
      request.method === 'POST',
    );
    if (!playerId) return json(env, 204, {});

    if (request.method === 'DELETE') {
      await env.DB.prepare('DELETE FROM ranked_queue WHERE player_id = ?')
        .bind(playerId)
        .run();
      return json(env, 200, { status: 'cancelled' });
    }

    const body = await readJsonObject(request);
    const difficulty = requiredDifficulty(body.difficulty);
    const variant = normalizeDuelVariant(body.variant, 'classic9');
    const balance = await ensureStarterGrant(env, playerId);
    const entryFee = entryFeeForDifficulty(difficulty);
    if (balance < entryFee) {
      throw new EconomyError(
        409,
        `You need at least ${entryFee} Coins to enter this online match.`,
        'insufficient_coins',
      );
    }
    const rating = await ratingForMatchmaking(
      env,
      playerId,
      difficulty,
      variant,
    );
    const payload: MatchmakingRequest = {
      playerId,
      difficulty,
      variant,
      rating,
    };

    if (env.MATCHMAKING_QUEUE) {
      const id = env.MATCHMAKING_QUEUE.idFromName(`ranked-${variant}`);
      const stub = env.MATCHMAKING_QUEUE.get(id);
      const coordinated = await stub.fetch(
        new Request('https://matchmaking.internal/join', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(payload),
        }),
      );
      const responseBody = await safeJson(coordinated);
      return json(env, coordinated.status, responseBody);
    }

    const result = await coordinateRankedMatch(env, payload);
    return json(env, result.status === 'matched' ? 201 : 200, result);
  } catch (error) {
    return routeError(env, error);
  }
}

export class MatchmakingQueue {
  constructor(
    private readonly state: DurableObjectState,
    private readonly env: VariantMatchmakingEnv,
  ) {
    void this.state;
  }

  async fetch(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return internalJson(405, { error: 'Method not allowed.' });
    }
    try {
      const url = new URL(request.url);
      const body = await readJsonObject(request);

      // Legacy rematch acceptance serializes funding through this same Durable
      // Object. entry_v2 exports this class in production, so /fund must remain
      // compatible even though ranked queue joins are variant-aware now.
      if (url.pathname === '/fund') {
        const mode = requiredInternalString(body.mode, 'mode');
        if (mode !== 'friendly' && mode !== 'ranked') {
          throw new EconomyError(400, 'Invalid match mode.', 'invalid_mode');
        }
        const input: FundedMatchInput = {
          matchId: requiredInternalString(body.matchId, 'matchId'),
          roomId: requiredInternalString(body.roomId, 'roomId'),
          challengeId:
            typeof body.challengeId === 'string' && body.challengeId.trim()
              ? body.challengeId.trim()
              : null,
          mode,
          difficulty: requiredDifficulty(body.difficulty),
          variant: normalizeDuelVariant(body.variant, 'classic9'),
          playerAId: requiredInternalString(body.playerAId, 'playerAId'),
          playerBId: requiredInternalString(body.playerBId, 'playerBId'),
          now: requiredInternalString(body.now, 'now'),
        };
        await createFundedMatch(this.env, input);
        return internalJson(201, { ok: true, roomId: input.roomId });
      }

      if (url.pathname !== '/join') {
        return internalJson(404, { error: 'Coordinator route not found.' });
      }
      const playerId = requiredInternalString(body.playerId, 'playerId');
      const difficulty = requiredDifficulty(body.difficulty);
      const variant = normalizeDuelVariant(body.variant, 'classic9');
      const rating = Number(body.rating);
      if (!Number.isInteger(rating) || rating < 0 || rating > 10000) {
        throw new MatchmakingHttpError(400, 'Invalid rating.');
      }
      const result = await coordinateRankedMatch(this.env, {
        playerId,
        difficulty,
        variant,
        rating,
      });
      return internalJson(result.status === 'matched' ? 201 : 200, result);
    } catch (error) {
      const normalized = normalizeFundingError(error);
      if (
        normalized instanceof MatchmakingHttpError ||
        normalized instanceof EconomyError
      ) {
        return internalJson(normalized.status, {
          error: normalized.message,
          code: normalized instanceof EconomyError ? normalized.code : undefined,
        });
      }
      console.error('Variant matchmaking coordinator failed', normalized);
      return internalJson(500, {
        error: 'Matchmaking is temporarily unavailable.',
      });
    }
  }
}

async function coordinateRankedMatch(
  env: VariantMatchmakingEnv,
  input: MatchmakingRequest,
): Promise<MatchmakingResult> {
  const config = duelVariantConfig(input.variant);
  const nowMs = Date.now();
  const now = new Date(nowMs).toISOString();
  const staleMatchBefore = new Date(
    nowMs - MATCH_LOBBY_STALE_AFTER_MS,
  ).toISOString();
  await cancelStaleRankedLobbies(env, staleMatchBefore, now);
  const active = await env.DB.prepare(
    `SELECT room_id, difficulty, variant, board_size, cell_count
     FROM matches
     WHERE (player_a_id = ? OR player_b_id = ?)
       AND status IN (${ACTIVE_MATCH_STATUSES})
      ORDER BY created_at DESC
      LIMIT 1`,
  )
    .bind(input.playerId, input.playerId)
    .first<{
      room_id: string;
      difficulty: string;
      variant: DuelVariant;
      board_size: number;
      cell_count: number;
    }>();
  if (active?.room_id) {
    const activeVariant = normalizeDuelVariant(active.variant, 'classic9');
    const activeConfig = duelVariantConfig(activeVariant);
    return {
      status: 'matched',
      difficulty: active.difficulty,
      variant: activeVariant,
      boardSize: active.board_size || activeConfig.boardSize,
      cellCount: active.cell_count || activeConfig.cellCount,
      playerId: input.playerId,
      roomId: active.room_id,
      onlineCoins: await coinBalance(env, input.playerId),
    };
  }

  const ownBalance = await ensureStarterGrant(env, input.playerId);
  const entryFee = entryFeeForDifficulty(input.difficulty);
  if (ownBalance < entryFee) {
    await env.DB.prepare('DELETE FROM ranked_queue WHERE player_id = ?')
      .bind(input.playerId)
      .run();
    throw new EconomyError(
      409,
      `You need at least ${entryFee} Coins to enter this online match.`,
      'insufficient_coins',
    );
  }

  const staleBefore = new Date(nowMs - QUEUE_STALE_AFTER_MS).toISOString();
  const rankedPairCutoff = new Date(nowMs - RANKED_PAIR_WINDOW_MS).toISOString();
  await env.DB.prepare(
    `DELETE FROM ranked_queue
     WHERE room_id IS NOT NULL OR updated_at < ?`,
  )
    .bind(staleBefore)
    .run();

  const ownQueue = await env.DB.prepare(
    `SELECT joined_at
     FROM ranked_queue
     WHERE player_id = ?
       AND difficulty = ?
       AND variant = ?
       AND room_id IS NULL
     LIMIT 1`,
  )
    .bind(input.playerId, input.difficulty, input.variant)
    .first<{ joined_at: string }>();
  const parsedOwnJoinedAt = ownQueue?.joined_at
    ? Date.parse(ownQueue.joined_at)
    : nowMs;
  const ownJoinedAtMs = Number.isFinite(parsedOwnJoinedAt)
    ? parsedOwnJoinedAt
    : nowMs;
  const ownWaitMs = Math.max(0, nowMs - ownJoinedAtMs);
  const ownRatingDelta = matchmakingRatingDeltaForWaitMs(ownWaitMs);
  const fiveSecondsAgo = new Date(nowMs - MATCHMAKING_5_SECONDS_MS).toISOString();
  const tenSecondsAgo = new Date(nowMs - MATCHMAKING_10_SECONDS_MS).toISOString();
  const fifteenSecondsAgo = new Date(
    nowMs - MATCHMAKING_15_SECONDS_MS,
  ).toISOString();
  const twentySecondsAgo = new Date(
    nowMs - MATCHMAKING_20_SECONDS_MS,
  ).toISOString();

  let opponent: {
    player_id: string;
    rating: number;
    difficulty: string;
  } | null = null;
  let matchDifficulty = input.difficulty;
  for (let attempt = 0; attempt < 5; attempt++) {
    opponent = await env.DB.prepare(
      `SELECT q.player_id, q.rating, q.difficulty
       FROM ranked_queue q
       WHERE q.variant = ?
         AND q.player_id != ?
         AND q.room_id IS NULL
         AND q.updated_at >= ?
         AND ABS(q.rating - ?) <= ?
         AND ABS(q.rating - ?) <= CASE
           WHEN q.joined_at > ? THEN 150
           WHEN q.joined_at > ? THEN 300
           WHEN q.joined_at > ? THEN 500
           WHEN q.joined_at > ? THEN 750
           ELSE ?
         END
         AND NOT EXISTS (
           SELECT 1 FROM matches m
           WHERE (m.player_a_id = q.player_id OR m.player_b_id = q.player_id)
             AND m.status IN (${ACTIVE_MATCH_STATUSES})
         )
         AND NOT EXISTS (
           SELECT 1 FROM friendships b
           WHERE b.player_low_id = CASE WHEN q.player_id < ? THEN q.player_id ELSE ? END
             AND b.player_high_id = CASE WHEN q.player_id < ? THEN ? ELSE q.player_id END
             AND b.status = 'blocked'
         )
         AND (
           SELECT COUNT(*)
           FROM matches recent
           WHERE recent.mode = 'ranked'
             AND recent.rated = 1
             AND recent.finished_at IS NOT NULL
             AND recent.finished_at >= ?
             AND (
               (recent.player_a_id = q.player_id AND recent.player_b_id = ?)
               OR (recent.player_a_id = ? AND recent.player_b_id = q.player_id)
             )
         ) < ?
       ORDER BY
         CASE WHEN q.difficulty = ? THEN 0 ELSE 1 END,
         ABS(q.rating - ?),
         q.joined_at
       LIMIT 1`,
    )
      .bind(
        input.variant,
        input.playerId,
        staleBefore,
        input.rating,
        ownRatingDelta,
        input.rating,
        fiveSecondsAgo,
        tenSecondsAgo,
        fifteenSecondsAgo,
        twentySecondsAgo,
        MATCHMAKING_UNBOUNDED_RATING_DELTA,
        input.playerId,
        input.playerId,
        input.playerId,
        input.playerId,
        rankedPairCutoff,
        input.playerId,
        input.playerId,
        MAX_RATED_PAIR_MATCHES_24H,
        input.difficulty,
        input.rating,
      )
      .first<{ player_id: string; rating: number; difficulty: string }>();

    if (!opponent) break;
    matchDifficulty = easierDifficulty(input.difficulty, opponent.difficulty);
    const matchedEntryFee = entryFeeForDifficulty(matchDifficulty);
    const opponentBalance = await ensureStarterGrant(env, opponent.player_id);
    if (ownBalance >= matchedEntryFee && opponentBalance >= matchedEntryFee) {
      break;
    }
    await env.DB.prepare('DELETE FROM ranked_queue WHERE player_id = ?')
      .bind(opponent.player_id)
      .run();
    opponent = null;
  }

  if (!opponent) {
    await env.DB.prepare(
      `INSERT INTO ranked_queue (
         player_id, difficulty, variant, rating, joined_at, updated_at
       ) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(player_id) DO UPDATE SET
         difficulty = excluded.difficulty,
         variant = excluded.variant,
         rating = excluded.rating,
         joined_at = CASE
           WHEN ranked_queue.difficulty != excluded.difficulty
             OR ranked_queue.variant != excluded.variant
             THEN excluded.joined_at
           ELSE ranked_queue.joined_at
         END,
         updated_at = excluded.updated_at,
         room_id = NULL,
         matched_player_id = NULL`,
    )
      .bind(
        input.playerId,
        input.difficulty,
        input.variant,
        input.rating,
        now,
        now,
      )
      .run();
    return {
      status: 'queued',
      difficulty: input.difficulty,
      variant: input.variant,
      boardSize: config.boardSize,
      cellCount: config.cellCount,
      playerId: input.playerId,
      rating: input.rating,
      onlineCoins: ownBalance,
    };
  }

  const roomId = roomIdForVariant(input.variant);
  const matchId = crypto.randomUUID();
  try {
    await createVariantFundedMatch(
      env,
      {
        matchId,
        roomId,
        challengeId: null,
        mode: 'ranked',
        difficulty: matchDifficulty,
        variant: input.variant,
        playerAId: opponent.player_id,
        playerBId: input.playerId,
        now,
      },
      input.variant,
    );
  } catch (error) {
    throw normalizeFundingError(error);
  }

  return {
    status: 'matched',
    difficulty: matchDifficulty,
    variant: input.variant,
    boardSize: config.boardSize,
    cellCount: config.cellCount,
    playerId: input.playerId,
    roomId,
    onlineCoins: await coinBalance(env, input.playerId),
  };
}

function easierDifficulty(left: string, right: string): string {
  return difficultyRank(left) <= difficultyRank(right) ? left : right;
}

function difficultyRank(value: string): number {
  const index = DIFFICULTY_ORDER.indexOf(value);
  return index < 0 ? DIFFICULTY_ORDER.length : index;
}

async function cancelStaleRankedLobbies(
  env: VariantMatchmakingEnv,
  staleBefore: string,
  now: string,
): Promise<void> {
  await env.DB.prepare(
    `UPDATE matches
     SET status = 'cancelled',
         finished_at = COALESCE(finished_at, ?),
         finish_reason = COALESCE(finish_reason, 'lobby_timeout'),
         updated_at = ?
     WHERE mode = 'ranked'
       AND status = 'waiting'
       AND started_at IS NULL
       AND created_at < ?`,
  )
    .bind(now, now, staleBefore)
    .run();
}

async function createVariantFundedMatch(
  env: VariantMatchmakingEnv,
  input: FundedMatchInput,
  variant: DuelVariant,
): Promise<void> {
  await createFundedMatch(env, input);
  const config = duelVariantConfig(variant);
  await env.DB.prepare(
    `UPDATE matches
     SET variant = ?, board_size = ?, cell_count = ?, updated_at = ?
     WHERE id = ?`,
  )
    .bind(
      variant,
      config.boardSize,
      config.cellCount,
      input.now,
      input.matchId,
    )
    .run();
}

async function ratingForMatchmaking(
  env: VariantMatchmakingEnv,
  playerId: string,
  difficulty: string,
  variant: DuelVariant,
): Promise<number> {
  // Visible RP and its rank-alignment targets are based on the authoritative
  // global hidden MMR snapshot. Keep queue pairing on that same global skill
  // signal; difficulty scopes continue to update for per-difficulty stats.
  void difficulty;
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO player_variant_ratings (
       player_id, variant, scope, updated_at
     ) VALUES (?, ?, 'global', ?)
     ON CONFLICT(player_id, variant, scope) DO NOTHING`,
  )
    .bind(playerId, variant, now)
    .run();
  const row = await env.DB.prepare(
    `SELECT rating FROM player_variant_ratings
     WHERE player_id = ? AND variant = ? AND scope = 'global'`,
  )
    .bind(playerId, variant)
    .first<{ rating: number }>();
  return row?.rating ?? 1000;
}

async function ensurePlayerId(
  request: Request,
  env: VariantMatchmakingEnv,
  ctx: ExecutionContext,
  uid: string,
  legacyFetch: LegacyFetch,
  createIfMissing: boolean,
): Promise<string | null> {
  let current = await env.DB.prepare(
    'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
  )
    .bind(uid)
    .first<{ id: string }>();
  if (current || !createIfMissing) return current?.id ?? null;

  const headers = new Headers(request.headers);
  headers.set('content-type', 'application/json');
  const profileUrl = new URL('/v1/me', request.url);
  const response = await legacyFetch(
    new Request(profileUrl, {
      method: 'POST',
      headers,
      body: '{}',
    }),
    env,
    ctx,
  );
  if (!response.ok) {
    throw new EconomyError(
      response.status,
      'Unable to create the player profile.',
    );
  }
  current = await env.DB.prepare(
    'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
  )
    .bind(uid)
    .first<{ id: string }>();
  if (!current) {
    throw new EconomyError(500, 'Unable to create the player profile.');
  }
  return current.id;
}

async function authenticateFirebase(
  request: Request,
  env: VariantMatchmakingEnv,
): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) throw new Error('Missing bearer token.');
  const token = header.slice(7).trim();
  if (!token) throw new Error('Missing bearer token.');
  const issuer = `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`;
  const verified = await jwtVerify(token, FIREBASE_JWKS, {
    algorithms: ['RS256'],
    issuer,
    audience: env.FIREBASE_PROJECT_ID,
  });
  const uid = verified.payload.sub;
  if (!uid) throw new Error('Invalid Firebase identity.');
  return uid;
}

async function readJsonObject(
  request: Request,
): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('Invalid object.');
    }
    return value as Record<string, unknown>;
  } catch {
    throw new MatchmakingHttpError(400, 'Invalid JSON body.');
  }
}

function requiredDifficulty(value: unknown): string {
  if (typeof value !== 'string' || !DIFFICULTIES.has(value.trim())) {
    throw new MatchmakingHttpError(400, 'Invalid difficulty.');
  }
  return value.trim();
}

function requiredInternalString(value: unknown, field: string): string {
  if (typeof value !== 'string') {
    throw new MatchmakingHttpError(400, `${field} is required.`);
  }
  const clean = value.trim();
  if (!clean || clean.length > 8192) {
    throw new MatchmakingHttpError(400, `${field} is invalid.`);
  }
  return clean;
}

function normalizeFundingError(error: unknown): unknown {
  if (error instanceof EconomyError || error instanceof MatchmakingHttpError) {
    return error;
  }
  const message = String(error);
  if (message.includes('active_match_conflict')) {
    return new EconomyError(
      409,
      'Finish or cancel the active online match first.',
      'active_match_conflict',
    );
  }
  if (message.includes('ranked_pair_limit')) {
    return new EconomyError(
      409,
      'Ranked rematch limit reached for this opponent. Find a different ranked opponent.',
      'ranked_pair_limit',
    );
  }
  if (
    message.includes('negative_coin_balance') ||
    message.includes('coin_debit_balance_invariant') ||
    message.includes('match_entry_balance_invariant')
  ) {
    return new EconomyError(409, 'Not enough Coins.', 'insufficient_coins');
  }
  return error;
}

class MatchmakingHttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function safeJson(
  response: Response,
): Promise<Record<string, unknown>> {
  try {
    const value = await response.json();
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

function routeError(env: VariantMatchmakingEnv, error: unknown): Response {
  if (error instanceof AppCheckError) {
    return json(env, 403, { error: error.code, code: error.code });
  }
  const normalized = normalizeFundingError(error);
  if (normalized instanceof EconomyError) {
    return json(env, normalized.status, { error: normalized.message, code: normalized.code });
  }
  if (normalized instanceof MatchmakingHttpError) {
    return json(env, normalized.status, { error: normalized.message });
  }
  const message = normalized instanceof Error ? normalized.message : '';
  const unauthorized =
    message.includes('bearer') ||
    message.includes('Firebase') ||
    message.includes('identity');
  console.error('Variant matchmaking route failed', normalized);
  return json(env, unauthorized ? 401 : 503, {
    error: unauthorized
      ? 'The player session is unavailable.'
      : 'Matchmaking is temporarily unavailable.',
  });
}

function internalJson(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function json(
  env: VariantMatchmakingEnv,
  status: number,
  body: unknown,
): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
      'access-control-allow-headers':
        'authorization, content-type, x-firebase-appcheck',
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
    },
  });
}
