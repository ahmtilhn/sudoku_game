import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';
import worker, { Env, GameRoom, MatchmakingQueue } from './index';

export { GameRoom };
export { MatchmakingQueue };

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

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
