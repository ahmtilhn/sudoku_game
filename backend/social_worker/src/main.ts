import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';
import {
  EconomyError,
  claimAchievementReward,
  claimDailyLogin,
  coinBalance,
  confirmAdReward,
  createFundedMatch,
  createRematchInvitation,
  ensureStarterGrant,
  entryFeeForDifficulty,
  grantTestPurchase,
  ledgerPage,
  markRematchStatus,
  pendingRematches,
  prepareAdReward,
  rematchForResponse,
  rematchJson,
  spendCareerContinue,
  walletSnapshot,
  type FundedMatchInput,
} from './economy';
import { roomIdForVariant } from './online_duel_factory';
import worker, { Env, GameRoom } from './index';
import { normalizeDuelVariant } from './sudoku_variant';

export { GameRoom };

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

const ACTIVE_MATCH_STATUSES = "'waiting', 'countdown', 'active', 'paused'";
const QUEUE_STALE_AFTER_MS = 2 * 60 * 1000;

// Economy.ts intentionally accepts optional deployment variables without
// forcing every local wrangler configuration to define them.
type RuntimeEnv = Env & {
  ALLOW_TEST_PURCHASE_GRANTS?: string;
};

type MatchmakingRequest = {
  playerId: string;
  difficulty: string;
  rating: number;
};

type MatchmakingResult = {
  status: 'queued' | 'matched';
  difficulty: string;
  playerId: string;
  rating?: number;
  roomId?: string;
  onlineCoins?: number;
};

export default {
  async fetch(
    request: Request,
    env: RuntimeEnv,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);

    if (
      /^\/v1\/rooms\/[^/]+\/connect$/.test(url.pathname) &&
      request.method === 'GET'
    ) {
      return connectRoomWithoutResponseWrapping(request, env, url);
    }

    if (
      url.pathname === '/v1/matchmaking/queue' &&
      request.method === 'POST'
    ) {
      return joinRankedQueueSerialized(request, env, ctx);
    }

    if (url.pathname === '/v1/me' && request.method === 'POST') {
      return profileWithWallet(request, env, ctx);
    }

    if (isEconomyRoute(url.pathname)) {
      return handleEconomyRoute(request, env, ctx, url);
    }

    if (
      url.pathname === '/v1/friends/requests' &&
      request.method === 'GET'
    ) {
      try {
        await verifyAppCheckRequest(request, env);
        const uid = await authenticateFirebase(request, env);
        const current = await env.DB.prepare(
          'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
        )
          .bind(uid)
          .first<{ id: string }>();
        if (!current) return json(env, 404, { error: 'Player profile not found.' });

        const rows = await env.DB.prepare(
          `SELECT p.*,
             'pending' AS friendship_status
           FROM friendships f
           JOIN players p ON p.id = f.requester_id
           WHERE (f.player_low_id = ? OR f.player_high_id = ?)
             AND f.status = 'pending'
             AND f.requester_id != ?
           ORDER BY f.created_at DESC
           LIMIT 100`,
        )
          .bind(current.id, current.id, current.id)
          .all<Record<string, unknown>>();

        return json(env, 200, {
          players: rows.results.map((row) => ({
            publicId: row.public_id,
            username: row.username,
            displayName: row.display_name,
            avatarKey: row.avatar_key,
            rating: row.rating,
            gamesPlayed: row.games_played,
            wins: row.wins,
            losses: row.losses,
            achievementCount: row.achievement_count,
            friendshipStatus: 'pending',
          })),
        });
      } catch (error) {
        return routeError(env, error);
      }
    }

    return worker.fetch(request, env, ctx);
  },
};

function isEconomyRoute(pathname: string): boolean {
  return (
    pathname === '/v1/me/wallet' ||
    pathname === '/v1/me/wallet/ledger' ||
    pathname === '/v1/me/wallet/spend/career-continue' ||
    pathname === '/v1/rewards/daily-login/claim' ||
    pathname === '/v1/rewards/daily-ad/prepare' ||
    pathname === '/v1/rewards/daily-ad/confirm' ||
    pathname === '/v1/rewards/career-ad/prepare' ||
    pathname === '/v1/rewards/career-ad/confirm' ||
    pathname === '/v1/rematches/pending' ||
    /^\/v1\/achievements\/[^/]+\/claim$/.test(pathname) ||
    /^\/v1\/matches\/[^/]+\/rematch$/.test(pathname) ||
    /^\/v1\/rematches\/[^/]+\/respond$/.test(pathname) ||
    pathname === '/v1/purchases/google/verify' ||
    pathname === '/v1/purchases/apple/verify'
  );
}

async function profileWithWallet(
  request: Request,
  env: RuntimeEnv,
  ctx: ExecutionContext,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    const response = await worker.fetch(request, env, ctx);
    if (!response.ok) return response;
    const profile = (await response.json()) as Record<string, unknown>;
    const playerId = await ensurePlayerId(request, env, ctx, uid);
    const wallet = await walletSnapshot(env, playerId);
    return json(env, 200, { ...profile, onlineCoins: wallet.balance, wallet });
  } catch (error) {
    return routeError(env, error);
  }
}

async function handleEconomyRoute(
  request: Request,
  env: RuntimeEnv,
  ctx: ExecutionContext,
  url: URL,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    const playerId = await ensurePlayerId(request, env, ctx, uid);

    if (url.pathname === '/v1/me/wallet' && request.method === 'GET') {
      return json(env, 200, await walletSnapshot(env, playerId));
    }

    if (url.pathname === '/v1/me/wallet/ledger' && request.method === 'GET') {
      const rawLimit = Number(url.searchParams.get('limit') ?? '50');
      const limit = Number.isFinite(rawLimit) ? rawLimit : 50;
      return json(env, 200, await ledgerPage(env, playerId, limit));
    }

    if (
      url.pathname === '/v1/me/wallet/spend/career-continue' &&
      request.method === 'POST'
    ) {
      const body = await readJsonObject(request);
      const requestId = requiredInternalString(body.requestId, 'requestId');
      return json(env, 200, await spendCareerContinue(env, playerId, requestId));
    }

    if (
      url.pathname === '/v1/rewards/daily-login/claim' &&
      request.method === 'POST'
    ) {
      return json(env, 200, await claimDailyLogin(env, playerId));
    }

    if (
      url.pathname === '/v1/rewards/daily-ad/prepare' &&
      request.method === 'POST'
    ) {
      return json(
        env,
        201,
        await prepareAdReward(env, playerId, 'daily_rewarded_ad'),
      );
    }

    if (
      url.pathname === '/v1/rewards/daily-ad/confirm' &&
      request.method === 'POST'
    ) {
      const body = await readJsonObject(request);
      const token = requiredInternalString(body.token, 'token');
      return json(env, 200, await confirmAdReward(env, playerId, token));
    }

    if (
      url.pathname === '/v1/rewards/career-ad/prepare' &&
      request.method === 'POST'
    ) {
      return json(
        env,
        201,
        await prepareAdReward(env, playerId, 'career_rewarded_ad'),
      );
    }

    if (
      url.pathname === '/v1/rewards/career-ad/confirm' &&
      request.method === 'POST'
    ) {
      const body = await readJsonObject(request);
      const token = requiredInternalString(body.token, 'token');
      return json(env, 200, await confirmAdReward(env, playerId, token));
    }

    if (
      /^\/v1\/achievements\/[^/]+\/claim$/.test(url.pathname) &&
      request.method === 'POST'
    ) {
      const achievementId = decodeURIComponent(url.pathname.split('/')[3]);
      return json(
        env,
        200,
        await claimAchievementReward(env, playerId, achievementId),
      );
    }

    if (
      /^\/v1\/matches\/[^/]+\/rematch$/.test(url.pathname) &&
      request.method === 'POST'
    ) {
      const matchId = decodeURIComponent(url.pathname.split('/')[3]);
      return json(
        env,
        201,
        await createRematchInvitation(env, playerId, matchId),
      );
    }

    if (url.pathname === '/v1/rematches/pending' && request.method === 'GET') {
      return json(env, 200, await pendingRematches(env, playerId));
    }

    if (
      /^\/v1\/rematches\/[^/]+\/respond$/.test(url.pathname) &&
      request.method === 'POST'
    ) {
      const invitationId = decodeURIComponent(url.pathname.split('/')[3]);
      const body = await readJsonObject(request);
      const action = requiredInternalString(body.action, 'action');
      if (action !== 'accept' && action !== 'decline') {
        throw new EconomyError(400, 'Rematch action must be accept or decline.');
      }
      const invitation = await rematchForResponse(env, invitationId, playerId, {
        allowAccepted: action === 'accept',
      });
      if (action === 'decline') {
        await markRematchStatus(env, invitation.id, 'declined', null);
        return json(env, 200, await rematchJson(env, invitation.id, playerId));
      }
      if (invitation.status === 'accepted' && invitation.room_id) {
        return json(env, 200, await rematchJson(env, invitation.id, playerId));
      }

      const variant = normalizeDuelVariant(invitation.variant, 'classic9');
      const roomId = roomIdForVariant(variant);
      const matchId = crypto.randomUUID();
      const funded: FundedMatchInput = {
        matchId,
        roomId,
        challengeId: null,
        mode: invitation.mode === 'ranked' ? 'ranked' : 'friendly',
        difficulty: invitation.difficulty,
        variant,
        playerAId: invitation.sender_id,
        playerBId: invitation.recipient_id,
        now: new Date().toISOString(),
      };
      try {
        await fundMatchSerialized(env, funded);
      } catch (error) {
        if (error instanceof EconomyError && error.code === 'insufficient_coins') {
          await markRematchStatus(env, invitation.id, 'insufficient_coins', null);
        }
        throw error;
      }
      await markRematchStatus(env, invitation.id, 'accepted', roomId);
      return json(env, 201, await rematchJson(env, invitation.id, playerId));
    }

    if (
      (url.pathname === '/v1/purchases/google/verify' ||
        url.pathname === '/v1/purchases/apple/verify') &&
      request.method === 'POST'
    ) {
      const body = await readJsonObject(request);
      const platform = url.pathname.includes('/google/') ? 'android' : 'ios';
      return json(
        env,
        200,
        await grantTestPurchase(env, {
          playerId,
          platform,
          productId: requiredInternalString(body.productId, 'productId'),
          transactionId: requiredInternalString(
            body.transactionId,
            'transactionId',
          ),
          verificationData: requiredInternalString(
            body.verificationData,
            'verificationData',
          ),
        }),
      );
    }

    return json(env, 405, { error: 'Method not allowed.' });
  } catch (error) {
    return routeError(env, error);
  }
}

async function ensurePlayerId(
  request: Request,
  env: RuntimeEnv,
  ctx: ExecutionContext,
  uid: string,
): Promise<string> {
  let current = await env.DB.prepare(
    'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
  )
    .bind(uid)
    .first<{ id: string }>();
  if (current) return current.id;

  const headers = new Headers(request.headers);
  headers.set('content-type', 'application/json');
  const profileUrl = new URL('/v1/me', request.url);
  const response = await worker.fetch(
    new Request(profileUrl, {
      method: 'POST',
      headers,
      body: '{}',
    }),
    env,
    ctx,
  );
  if (!response.ok) {
    throw new EconomyError(response.status, 'Unable to create the player profile.');
  }
  current = await env.DB.prepare(
    'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
  )
    .bind(uid)
    .first<{ id: string }>();
  if (!current) throw new EconomyError(500, 'Unable to create the player profile.');
  return current.id;
}

async function joinRankedQueueSerialized(
  request: Request,
  env: RuntimeEnv,
  ctx: ExecutionContext,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    const body = await readJsonObject(request);
    const difficulty = requiredDifficulty(body.difficulty);
    const playerId = await ensurePlayerId(request, env, ctx, uid);
    const balance = await ensureStarterGrant(env, playerId);
    const entryFee = entryFeeForDifficulty(difficulty);
    if (balance < entryFee) {
      throw new EconomyError(
        409,
        `You need at least ${entryFee} Coins to enter this online match.`,
        'insufficient_coins',
      );
    }

    const rating = await ratingForMatchmaking(env, playerId, difficulty);
    const payload: MatchmakingRequest = {
      playerId,
      difficulty,
      rating,
    };

    if (env.MATCHMAKING_QUEUE) {
      const id = env.MATCHMAKING_QUEUE.idFromName('ranked-global');
      const stub = env.MATCHMAKING_QUEUE.get(id);
      const coordinated = await stub.fetch(
        new Request('https://matchmaking.internal/join', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(payload),
        }),
      );
      return coordinatorResponse(env, coordinated);
    }

    const result = await coordinateRankedMatch(env, payload);
    return json(env, result.status === 'matched' ? 201 : 200, result);
  } catch (error) {
    return routeError(env, error);
  }
}

async function fundMatchSerialized(
  env: RuntimeEnv,
  input: FundedMatchInput,
): Promise<void> {
  if (!env.MATCHMAKING_QUEUE) {
    await createFundedMatch(env, input);
    return;
  }
  const id = env.MATCHMAKING_QUEUE.idFromName('ranked-global');
  const stub = env.MATCHMAKING_QUEUE.get(id);
  const response = await stub.fetch(
    new Request('https://matchmaking.internal/fund', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(input),
    }),
  );
  if (response.ok) return;
  const body = await safeJson(response);
  throw new EconomyError(
    response.status,
    String(body.error ?? 'Unable to fund the match.'),
    typeof body.code === 'string' ? body.code : undefined,
  );
}

async function coordinatorResponse(
  env: RuntimeEnv,
  response: Response,
): Promise<Response> {
  const body = await safeJson(response);
  return json(env, response.status, body);
}

async function connectRoomWithoutResponseWrapping(
  request: Request,
  env: RuntimeEnv,
  url: URL,
): Promise<Response> {
  if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
    return json(env, 426, { error: 'WebSocket upgrade required.' });
  }

  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    const player = await env.DB.prepare(
      'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
    )
      .bind(uid)
      .first<{ id: string }>();
    if (!player) return json(env, 404, { error: 'Player profile not found.' });

    const roomId = decodeURIComponent(url.pathname.split('/')[3] ?? '');
    const match = await env.DB.prepare(
      `SELECT player_a_id, player_b_id, status
       FROM matches
       WHERE room_id = ?
         AND status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')
       LIMIT 1`,
    )
      .bind(roomId)
      .first<{ player_a_id: string; player_b_id: string; status: string }>();
    if (!match) return json(env, 404, { error: 'Game room not found.' });
    if (
      match.player_a_id !== player.id &&
      match.player_b_id !== player.id
    ) {
      return json(env, 403, { error: 'You are not a participant in this room.' });
    }

    const id = env.GAME_ROOMS.idFromName(roomId);
    const stub = env.GAME_ROOMS.get(id);
    const headers = new Headers(request.headers);
    headers.set('x-sudoku-player-id', player.id);
    headers.set('x-sudoku-room-id', roomId);
    return stub.fetch(new Request(request.url, { method: 'GET', headers }));
  } catch (error) {
    return routeError(env, error);
  }
}

export class MatchmakingQueue {
  constructor(
    private readonly state: DurableObjectState,
    private readonly env: RuntimeEnv,
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
      if (url.pathname === '/join') {
        const playerId = requiredInternalString(body.playerId, 'playerId');
        const difficulty = requiredDifficulty(body.difficulty);
        const rating = Number(body.rating);
        if (!Number.isInteger(rating) || rating < 0 || rating > 10000) {
          throw new MatchmakingHttpError(400, 'Invalid rating.');
        }
        const result = await coordinateRankedMatch(this.env, {
          playerId,
          difficulty,
          rating,
        });
        return internalJson(result.status === 'matched' ? 201 : 200, result);
      }

      if (url.pathname === '/fund') {
        const mode = requiredInternalString(body.mode, 'mode');
        if (mode !== 'friendly' && mode !== 'ranked') {
          throw new EconomyError(400, 'Invalid match mode.');
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

      return internalJson(404, { error: 'Coordinator route not found.' });
    } catch (error) {
      if (error instanceof MatchmakingHttpError || error instanceof EconomyError) {
        return internalJson(error.status, {
          error: error.message,
          code: error instanceof EconomyError ? error.code : undefined,
        });
      }
      console.error('Matchmaking coordinator failed', error);
      return internalJson(500, { error: 'Matchmaking coordinator failed.' });
    }
  }
}

async function coordinateRankedMatch(
  env: RuntimeEnv,
  input: MatchmakingRequest,
): Promise<MatchmakingResult> {
  const active = await env.DB.prepare(
    `SELECT room_id, difficulty
     FROM matches
     WHERE (player_a_id = ? OR player_b_id = ?)
       AND status IN (${ACTIVE_MATCH_STATUSES})
     ORDER BY created_at DESC
     LIMIT 1`,
  )
    .bind(input.playerId, input.playerId)
    .first<{ room_id: string; difficulty: string }>();
  if (active?.room_id) {
    return {
      status: 'matched',
      difficulty: active.difficulty,
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

  const now = new Date().toISOString();
  const staleBefore = new Date(Date.now() - QUEUE_STALE_AFTER_MS).toISOString();
  await env.DB.prepare(
    `DELETE FROM ranked_queue
     WHERE room_id IS NOT NULL OR updated_at < ?`,
  )
    .bind(staleBefore)
    .run();

  let opponent: { player_id: string; rating: number } | null = null;
  for (let attempt = 0; attempt < 5; attempt++) {
    opponent = await env.DB.prepare(
      `SELECT q.player_id, q.rating
       FROM ranked_queue q
       WHERE q.difficulty = ?
         AND q.player_id != ?
         AND q.room_id IS NULL
         AND q.updated_at >= ?
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
       ORDER BY ABS(q.rating - ?), q.joined_at
       LIMIT 1`,
    )
      .bind(
        input.difficulty,
        input.playerId,
        staleBefore,
        input.playerId,
        input.playerId,
        input.playerId,
        input.playerId,
        input.rating,
      )
      .first<{ player_id: string; rating: number }>();

    if (!opponent) break;
    const opponentBalance = await ensureStarterGrant(env, opponent.player_id);
    if (opponentBalance >= entryFee) break;
    await env.DB.prepare('DELETE FROM ranked_queue WHERE player_id = ?')
      .bind(opponent.player_id)
      .run();
    opponent = null;
  }

  if (!opponent) {
    await env.DB.prepare(
      `INSERT INTO ranked_queue (player_id, difficulty, rating, joined_at, updated_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(player_id) DO UPDATE SET
         difficulty = excluded.difficulty,
         rating = excluded.rating,
         joined_at = CASE
           WHEN ranked_queue.difficulty != excluded.difficulty
             THEN excluded.joined_at
           ELSE ranked_queue.joined_at
         END,
         updated_at = excluded.updated_at,
         room_id = NULL,
         matched_player_id = NULL`,
    )
      .bind(input.playerId, input.difficulty, input.rating, now, now)
      .run();
    return {
      status: 'queued',
      difficulty: input.difficulty,
      playerId: input.playerId,
      rating: input.rating,
      onlineCoins: ownBalance,
    };
  }

  const roomId = crypto.randomUUID();
  const matchId = crypto.randomUUID();
  await createFundedMatch(env, {
    matchId,
    roomId,
    challengeId: null,
    mode: 'ranked',
    difficulty: input.difficulty,
    playerAId: opponent.player_id,
    playerBId: input.playerId,
    now,
  });

  return {
    status: 'matched',
    difficulty: input.difficulty,
    playerId: input.playerId,
    roomId,
    onlineCoins: await coinBalance(env, input.playerId),
  };
}

async function ratingForMatchmaking(
  env: RuntimeEnv,
  playerId: string,
  difficulty: string,
): Promise<number> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO player_ratings (player_id, scope, updated_at)
     VALUES (?, ?, ?)
     ON CONFLICT(player_id, scope) DO NOTHING`,
  )
    .bind(playerId, difficulty, now)
    .run();
  const row = await env.DB.prepare(
    'SELECT rating FROM player_ratings WHERE player_id = ? AND scope = ?',
  )
    .bind(playerId, difficulty)
    .first<{ rating: number }>();
  return row?.rating ?? 1000;
}

async function authenticateFirebase(
  request: Request,
  env: RuntimeEnv,
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

class MatchmakingHttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function safeJson(response: Response): Promise<Record<string, unknown>> {
  try {
    const value = await response.json();
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

function routeError(env: RuntimeEnv, error: unknown): Response {
  if (error instanceof AppCheckError) {
    return json(env, 403, { error: error.code, code: error.code });
  }
  if (error instanceof EconomyError) {
    return json(env, error.status, { error: error.message, code: error.code });
  }
  if (error instanceof MatchmakingHttpError) {
    return json(env, error.status, { error: error.message });
  }
  const message = error instanceof Error ? error.message : 'Unauthorized.';
  const status =
    message.includes('bearer') ||
    message.includes('Firebase') ||
    message.includes('identity')
      ? 401
      : 500;
  console.error('worker route failed', error);
  return json(env, status, { error: message });
}

function internalJson(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function json(env: RuntimeEnv, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
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
