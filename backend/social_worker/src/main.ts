import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';
import worker, { Env, GameRoom } from './index';

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
};

export default {
  async fetch(
    request: Request,
    env: Env,
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
        if (error instanceof AppCheckError) {
          return json(env, 403, { error: error.code });
        }
        return json(env, 401, {
          error: error instanceof Error ? error.message : 'Unauthorized.',
        });
      }
    }

    return worker.fetch(request, env, ctx);
  },
};

async function joinRankedQueueSerialized(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    const body = await readJsonObject(request);
    const difficulty = requiredDifficulty(body.difficulty);

    // Reuse the existing profile creation path without allowing the old,
    // non-serialized matchmaking implementation to run.
    const profileHeaders = new Headers(request.headers);
    profileHeaders.set('content-type', 'application/json');
    const profileUrl = new URL('/v1/me', request.url);
    const profileResponse = await worker.fetch(
      new Request(profileUrl, {
        method: 'POST',
        headers: profileHeaders,
        body: '{}',
      }),
      env,
      ctx,
    );
    if (!profileResponse.ok) return profileResponse;

    const current = await env.DB.prepare(
      'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
    )
      .bind(uid)
      .first<{ id: string }>();
    if (!current) {
      return json(env, 500, { error: 'Unable to create the player profile.' });
    }

    const rating = await ratingForMatchmaking(
      env,
      current.id,
      difficulty,
    );
    const payload: MatchmakingRequest = {
      playerId: current.id,
      difficulty,
      rating,
    };

    let result: MatchmakingResult;
    if (env.MATCHMAKING_QUEUE) {
      // One global Durable Object serializes every ranked queue mutation.
      // This removes the race where two devices both observe an empty queue.
      const id = env.MATCHMAKING_QUEUE.idFromName('ranked-global');
      const stub = env.MATCHMAKING_QUEUE.get(id);
      const coordinated = await stub.fetch(
        new Request('https://matchmaking.internal/join', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(payload),
        }),
      );
      const coordinatedBody = await coordinated.text();
      let decoded: unknown = {};
      try {
        decoded = coordinatedBody ? JSON.parse(coordinatedBody) : {};
      } catch {
        return json(env, 502, { error: 'Invalid matchmaking coordinator response.' });
      }
      return json(env, coordinated.status, decoded);
    }

    result = await coordinateRankedMatch(env, payload);
    return json(env, result.status === 'matched' ? 201 : 200, result);
  } catch (error) {
    if (error instanceof AppCheckError) {
      return json(env, 403, { error: error.code });
    }
    if (error instanceof MatchmakingHttpError) {
      return json(env, error.status, { error: error.message });
    }
    return json(env, 401, {
      error: error instanceof Error ? error.message : 'Unauthorized.',
    });
  }
}

async function connectRoomWithoutResponseWrapping(
  request: Request,
  env: Env,
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

    const roomId = url.pathname.split('/')[3];
    const match = await env.DB.prepare(
      `SELECT player_a_id, player_b_id
       FROM matches
       WHERE room_id = ?
       LIMIT 1`,
    )
      .bind(roomId)
      .first<{ player_a_id: string; player_b_id: string }>();
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

    // Return the Durable Object's 101 response directly. Rebuilding this
    // response would drop the Cloudflare WebSocket attachment.
    return stub.fetch(new Request(request.url, { method: 'GET', headers }));
  } catch (error) {
    if (error instanceof AppCheckError) {
      return json(env, 403, { error: error.code });
    }
    return json(env, 401, {
      error: error instanceof Error ? error.message : 'Unauthorized.',
    });
  }
}

export class MatchmakingQueue {
  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {
    void this.state;
  }

  async fetch(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return internalJson(405, { error: 'Method not allowed.' });
    }

    try {
      const body = await readJsonObject(request);
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
    } catch (error) {
      if (error instanceof MatchmakingHttpError) {
        return internalJson(error.status, { error: error.message });
      }
      console.error('Matchmaking coordinator failed', error);
      return internalJson(500, { error: 'Matchmaking coordinator failed.' });
    }
  }
}

async function coordinateRankedMatch(
  env: Env,
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
    };
  }

  const now = new Date().toISOString();
  const staleBefore = new Date(Date.now() - QUEUE_STALE_AFTER_MS).toISOString();

  // Matched rows are never valid queue candidates. Old abandoned tickets are
  // also removed continuously rather than only by a one-time migration.
  await env.DB.prepare(
    `DELETE FROM ranked_queue
     WHERE room_id IS NOT NULL OR updated_at < ?`,
  )
    .bind(staleBefore)
    .run();

  const opponent = await env.DB.prepare(
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
    };
  }

  const roomId = crypto.randomUUID();
  const matchId = crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO matches (
         id, room_id, challenge_id, mode, difficulty, status,
         player_a_id, player_b_id, created_at, updated_at
       ) VALUES (?, ?, NULL, 'ranked', ?, 'waiting', ?, ?, ?, ?)`,
    ).bind(
      matchId,
      roomId,
      input.difficulty,
      opponent.player_id,
      input.playerId,
      now,
      now,
    ),
    env.DB.prepare(
      'DELETE FROM ranked_queue WHERE player_id IN (?, ?)',
    ).bind(opponent.player_id, input.playerId),
  ]);

  return {
    status: 'matched',
    difficulty: input.difficulty,
    playerId: input.playerId,
    roomId,
  };
}

async function ratingForMatchmaking(
  env: Env,
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

async function authenticateFirebase(request: Request, env: Env): Promise<string> {
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
  if (!clean || clean.length > 128) {
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

function internalJson(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function json(env: Env, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
      'access-control-allow-headers': 'authorization, content-type, x-firebase-appcheck',
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
    },
  });
}
