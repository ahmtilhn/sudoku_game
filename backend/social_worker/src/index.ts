import {
  SignJWT,
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
} from 'jose';

export interface Env {
  DB: D1Database;
  GAME_ROOMS: DurableObjectNamespace;
  FIREBASE_PROJECT_ID: string;
  FCM_PROJECT_ID: string;
  FCM_CLIENT_EMAIL: string;
  FCM_PRIVATE_KEY: string;
  ALLOWED_ORIGIN: string;
}

type PlayerRow = {
  id: string;
  firebase_uid: string;
  public_id: string;
  username: string;
  username_normalized: string;
  display_name: string;
  avatar_key: string;
  rating: number;
  games_played: number;
  wins: number;
  losses: number;
  achievement_count: number;
  created_at: string;
  updated_at: string;
  last_seen_at: string;
  friendship_status?: string | null;
  last_played_at?: string | null;
};

type ChallengeRow = {
  id: string;
  challenger_id: string;
  recipient_id: string;
  difficulty: string;
  status: string;
  room_id: string | null;
  created_at: string;
  updated_at: string;
  expires_at: string;
};

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

let cachedFcmAccessToken: { token: string; expiresAt: number } | null = null;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (request.method === 'OPTIONS') return corsResponse(env, new Response(null, { status: 204 }));

    try {
      const url = new URL(request.url);
      if (url.pathname === '/health') {
        return reply(env, { ok: true, service: 'sudoku-duel-social' });
      }

      const uid = await authenticateFirebase(request, env);
      const player = await ensurePlayer(env, uid, null);

      let response: Response;
      if (url.pathname === '/v1/me' && request.method === 'POST') {
        const body = await readJson(request);
        const updated = await ensurePlayer(env, uid, stringOrNull(body.displayName));
        response = reply(env, playerJson(updated));
      } else if (
        url.pathname === '/v1/me/devices/current' &&
        request.method === 'PUT'
      ) {
        response = await registerDevice(request, env, player);
      } else if (
        url.pathname === '/v1/me/devices/current' &&
        request.method === 'DELETE'
      ) {
        response = await disableDevice(request, env, player);
      } else if (
        url.pathname === '/v1/players/search' &&
        request.method === 'GET'
      ) {
        response = await searchPlayers(url, env, player);
      } else if (url.pathname === '/v1/friends' && request.method === 'GET') {
        response = await listFriends(env, player);
      } else if (
        url.pathname === '/v1/friends/requests' &&
        request.method === 'GET'
      ) {
        response = await listIncomingFriendRequests(env, player);
      } else if (
        url.pathname === '/v1/friends/requests' &&
        request.method === 'POST'
      ) {
        response = await createFriendRequest(request, env, player);
      } else if (
        url.pathname === '/v1/friends/requests/respond' &&
        request.method === 'POST'
      ) {
        response = await respondFriendRequest(request, env, player);
      } else if (
        url.pathname === '/v1/opponents/recent' &&
        request.method === 'GET'
      ) {
        response = await listRecentOpponents(env, player);
      } else if (url.pathname === '/v1/challenges' && request.method === 'POST') {
        response = await createChallenge(request, env, ctx, player);
      } else if (url.pathname === '/v1/challenges' && request.method === 'GET') {
        response = await listChallenges(url, env, player);
      } else if (
        /^\/v1\/challenges\/[^/]+\/respond$/.test(url.pathname) &&
        request.method === 'POST'
      ) {
        const challengeId = url.pathname.split('/')[3];
        response = await respondChallenge(request, env, ctx, player, challengeId);
      } else if (
        /^\/v1\/rooms\/[^/]+\/connect$/.test(url.pathname) &&
        request.method === 'GET'
      ) {
        const roomId = url.pathname.split('/')[3];
        response = await connectRoom(request, env, player, roomId);
      } else {
        response = errorReply(env, 404, 'Route not found.');
      }
      return corsResponse(env, response);
    } catch (error) {
      if (error instanceof HttpError) {
        return corsResponse(env, errorReply(env, error.status, error.message));
      }
      console.error(error);
      return corsResponse(env, errorReply(env, 500, 'Unexpected server error.'));
    }
  },
};

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function authenticateFirebase(request: Request, env: Env): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) throw new HttpError(401, 'Missing bearer token.');
  const token = header.slice(7).trim();
  if (!token) throw new HttpError(401, 'Missing bearer token.');

  const issuer = `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`;
  try {
    const verified = await jwtVerify(token, FIREBASE_JWKS, {
      algorithms: ['RS256'],
      issuer,
      audience: env.FIREBASE_PROJECT_ID,
    });
    const uid = verified.payload.sub;
    if (!uid) throw new Error('Missing subject.');
    return uid;
  } catch {
    throw new HttpError(401, 'Invalid or expired Firebase ID token.');
  }
}

async function ensurePlayer(
  env: Env,
  firebaseUid: string,
  requestedDisplayName: string | null,
): Promise<PlayerRow> {
  const existing = await env.DB.prepare(
    'SELECT * FROM players WHERE firebase_uid = ? LIMIT 1',
  )
    .bind(firebaseUid)
    .first<PlayerRow>();
  const now = new Date().toISOString();

  if (existing) {
    const displayName = requestedDisplayName
      ? sanitizeDisplayName(requestedDisplayName)
      : existing.display_name;
    await env.DB.prepare(
      'UPDATE players SET display_name = ?, updated_at = ?, last_seen_at = ? WHERE id = ?',
    )
      .bind(displayName, now, now, existing.id)
      .run();
    return { ...existing, display_name: displayName, updated_at: now, last_seen_at: now };
  }

  const id = crypto.randomUUID();
  const publicId = randomPublicId();
  const username = `player_${publicId.toLowerCase()}`;
  const displayName = sanitizeDisplayName(requestedDisplayName ?? 'Sudoku Player');
  await env.DB.prepare(
    `INSERT INTO players (
      id, firebase_uid, public_id, username, username_normalized,
      display_name, created_at, updated_at, last_seen_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      id,
      firebaseUid,
      publicId,
      username,
      username,
      displayName,
      now,
      now,
      now,
    )
    .run();

  const created = await env.DB.prepare('SELECT * FROM players WHERE id = ?')
    .bind(id)
    .first<PlayerRow>();
  if (!created) throw new HttpError(500, 'Unable to create player profile.');
  return created;
}

async function registerDevice(
  request: Request,
  env: Env,
  player: PlayerRow,
): Promise<Response> {
  const body = await readJson(request);
  const token = requiredString(body.token, 'token', 32, 4096);
  const platform = requiredString(body.platform, 'platform', 2, 16);
  if (platform !== 'android' && platform !== 'ios') {
    throw new HttpError(400, 'Unsupported device platform.');
  }
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO device_tokens (id, player_id, token, platform, enabled, created_at, updated_at)
     VALUES (?, ?, ?, ?, 1, ?, ?)
     ON CONFLICT(token) DO UPDATE SET
       player_id = excluded.player_id,
       platform = excluded.platform,
       enabled = 1,
       updated_at = excluded.updated_at`,
  )
    .bind(crypto.randomUUID(), player.id, token, platform, now, now)
    .run();
  return reply(env, { ok: true });
}

async function disableDevice(
  request: Request,
  env: Env,
  player: PlayerRow,
): Promise<Response> {
  const body = await readJson(request);
  const token = requiredString(body.token, 'token', 32, 4096);
  await env.DB.prepare(
    `UPDATE device_tokens
     SET enabled = 0, updated_at = ?
     WHERE player_id = ? AND token = ?`,
  )
    .bind(new Date().toISOString(), player.id, token)
    .run();
  return reply(env, { ok: true });
}

async function searchPlayers(
  url: URL,
  env: Env,
  current: PlayerRow,
): Promise<Response> {
  await enforceRateLimit(env, `search:${current.id}`, 30, 60);
  const query = normalizeUsername(url.searchParams.get('q') ?? '');
  if (query.length < 3) return reply(env, { players: [] });

  const rows = await env.DB.prepare(
    `SELECT p.*,
      (SELECT f.status FROM friendships f
       WHERE f.player_low_id = CASE WHEN p.id < ? THEN p.id ELSE ? END
         AND f.player_high_id = CASE WHEN p.id < ? THEN ? ELSE p.id END
       LIMIT 1) AS friendship_status
     FROM players p
     WHERE p.id != ?
       AND p.username_normalized LIKE ?
       AND NOT EXISTS (
         SELECT 1 FROM friendships b
         WHERE b.player_low_id = CASE WHEN p.id < ? THEN p.id ELSE ? END
           AND b.player_high_id = CASE WHEN p.id < ? THEN ? ELSE p.id END
           AND b.status = 'blocked'
       )
     ORDER BY CASE WHEN p.username_normalized = ? THEN 0 ELSE 1 END,
              p.rating DESC
     LIMIT 20`,
  )
    .bind(
      current.id,
      current.id,
      current.id,
      current.id,
      current.id,
      `%${query}%`,
      current.id,
      current.id,
      current.id,
      current.id,
      query,
    )
    .all<PlayerRow>();
  return reply(env, { players: rows.results.map(playerJson) });
}

async function listFriends(env: Env, current: PlayerRow): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT p.*, 'accepted' AS friendship_status
     FROM friendships f
     JOIN players p ON p.id = CASE
       WHEN f.player_low_id = ? THEN f.player_high_id
       ELSE f.player_low_id END
     WHERE (f.player_low_id = ? OR f.player_high_id = ?)
       AND f.status = 'accepted'
     ORDER BY p.display_name COLLATE NOCASE
     LIMIT 200`,
  )
    .bind(current.id, current.id, current.id)
    .all<PlayerRow>();
  return reply(env, { players: rows.results.map(playerJson) });
}

async function listIncomingFriendRequests(
  env: Env,
  current: PlayerRow,
): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT p.*, 'pending' AS friendship_status
     FROM friendships f
     JOIN players p ON p.id = f.requester_id
     WHERE (f.player_low_id = ? OR f.player_high_id = ?)
       AND f.status = 'pending'
       AND f.requester_id != ?
     ORDER BY f.created_at DESC
     LIMIT 100`,
  )
    .bind(current.id, current.id, current.id)
    .all<PlayerRow>();
  return reply(env, { players: rows.results.map(playerJson) });
}

async function createFriendRequest(
  request: Request,
  env: Env,
  current: PlayerRow,
): Promise<Response> {
  await enforceRateLimit(env, `friend:${current.id}`, 20, 3600);
  const body = await readJson(request);
  const target = await playerByPublicId(
    env,
    requiredString(body.targetPublicId, 'targetPublicId', 4, 64),
  );
  if (target.id === current.id) throw new HttpError(400, 'You cannot add yourself.');

  const [low, high] = orderedPair(current.id, target.id);
  const existing = await env.DB.prepare(
    'SELECT status FROM friendships WHERE player_low_id = ? AND player_high_id = ?',
  )
    .bind(low, high)
    .first<{ status: string }>();
  if (existing?.status === 'blocked') throw new HttpError(403, 'This player is unavailable.');

  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO friendships (
      player_low_id, player_high_id, requester_id, status, created_at, updated_at
    ) VALUES (?, ?, ?, 'pending', ?, ?)
    ON CONFLICT(player_low_id, player_high_id) DO UPDATE SET
      requester_id = excluded.requester_id,
      status = CASE WHEN friendships.status = 'accepted' THEN 'accepted' ELSE 'pending' END,
      updated_at = excluded.updated_at`,
  )
    .bind(low, high, current.id, now, now)
    .run();
  return reply(env, { ok: true }, 201);
}

async function respondFriendRequest(
  request: Request,
  env: Env,
  current: PlayerRow,
): Promise<Response> {
  const body = await readJson(request);
  const requester = await playerByPublicId(
    env,
    requiredString(body.requesterPublicId, 'requesterPublicId', 4, 64),
  );
  const action = requiredString(body.action, 'action', 4, 16);
  if (action !== 'accept' && action !== 'decline') {
    throw new HttpError(400, 'Friend action must be accept or decline.');
  }
  const [low, high] = orderedPair(current.id, requester.id);
  const relation = await env.DB.prepare(
    `SELECT requester_id, status FROM friendships
     WHERE player_low_id = ? AND player_high_id = ?`,
  )
    .bind(low, high)
    .first<{ requester_id: string; status: string }>();
  if (!relation || relation.status !== 'pending' || relation.requester_id !== requester.id) {
    throw new HttpError(404, 'Pending friend request not found.');
  }
  await env.DB.prepare(
    `UPDATE friendships SET status = ?, updated_at = ?
     WHERE player_low_id = ? AND player_high_id = ?`,
  )
    .bind(action === 'accept' ? 'accepted' : 'declined', new Date().toISOString(), low, high)
    .run();
  return reply(env, { ok: true });
}

async function listRecentOpponents(env: Env, current: PlayerRow): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT p.*, r.last_played_at
     FROM recent_opponents r
     JOIN players p ON p.id = CASE
       WHEN r.player_low_id = ? THEN r.player_high_id
       ELSE r.player_low_id END
     WHERE r.player_low_id = ? OR r.player_high_id = ?
     ORDER BY r.last_played_at DESC
     LIMIT 50`,
  )
    .bind(current.id, current.id, current.id)
    .all<PlayerRow>();
  return reply(env, { players: rows.results.map(playerJson) });
}

async function createChallenge(
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

  const id = crypto.randomUUID();
  const now = new Date();
  const expires = new Date(now.getTime() + 15 * 60 * 1000);
  await env.DB.prepare(
    `INSERT INTO challenges (
      id, challenger_id, recipient_id, difficulty, status,
      created_at, updated_at, expires_at
    ) VALUES (?, ?, ?, ?, 'pending', ?, ?, ?)`,
  )
    .bind(
      id,
      current.id,
      recipient.id,
      difficulty,
      now.toISOString(),
      now.toISOString(),
      expires.toISOString(),
    )
    .run();

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

async function listChallenges(
  url: URL,
  env: Env,
  current: PlayerRow,
): Promise<Response> {
  const requestedStatus = url.searchParams.get('status') ?? 'pending';
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE challenges SET status = 'expired', updated_at = ?
     WHERE status = 'pending' AND expires_at <= ?`,
  )
    .bind(now, now)
    .run();

  const rows = await env.DB.prepare(
    `SELECT * FROM challenges
     WHERE (challenger_id = ? OR recipient_id = ?) AND status = ?
     ORDER BY created_at DESC LIMIT 50`,
  )
    .bind(current.id, current.id, requestedStatus)
    .all<ChallengeRow>();
  const challenges = await Promise.all(rows.results.map((row) => challengeJson(env, row)));
  return reply(env, { challenges });
}

async function respondChallenge(
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

  const challenge = await challengeById(env, challengeId);
  if (challenge.recipient_id !== current.id) throw new HttpError(403, 'Only the recipient can respond.');
  if (challenge.status !== 'pending') throw new HttpError(409, 'Challenge is no longer pending.');
  if (new Date(challenge.expires_at).getTime() <= Date.now()) {
    await env.DB.prepare(
      `UPDATE challenges SET status = 'expired', updated_at = ? WHERE id = ?`,
    )
      .bind(new Date().toISOString(), challenge.id)
      .run();
    throw new HttpError(409, 'Challenge expired.');
  }

  const roomId = action === 'accept' ? crypto.randomUUID() : null;
  const status = action === 'accept' ? 'accepted' : 'declined';
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE challenges SET status = ?, room_id = ?, updated_at = ?
     WHERE id = ? AND status = 'pending'`,
  )
    .bind(status, roomId, now, challenge.id)
    .run();

  ctx.waitUntil(
    sendPlayerNotification(env, challenge.challenger_id, {
      title: status === 'accepted' ? 'Challenge accepted' : 'Challenge declined',
      body:
        status === 'accepted'
          ? `${current.display_name} accepted your Sudoku challenge.`
          : `${current.display_name} declined your Sudoku challenge.`,
      data: {
        type: 'challenge_response',
        challengeId: challenge.id,
        status,
        roomId: roomId ?? '',
      },
    }),
  );

  const updated = await challengeById(env, challenge.id);
  return reply(env, await challengeJson(env, updated));
}

async function connectRoom(
  request: Request,
  env: Env,
  current: PlayerRow,
  roomId: string,
): Promise<Response> {
  if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
    throw new HttpError(426, 'WebSocket upgrade required.');
  }
  const challenge = await env.DB.prepare(
    `SELECT * FROM challenges
     WHERE room_id = ? AND status = 'accepted' LIMIT 1`,
  )
    .bind(roomId)
    .first<ChallengeRow>();
  if (!challenge) throw new HttpError(404, 'Game room not found.');
  if (challenge.challenger_id !== current.id && challenge.recipient_id !== current.id) {
    throw new HttpError(403, 'You are not a participant in this room.');
  }

  const id = env.GAME_ROOMS.idFromName(roomId);
  const stub = env.GAME_ROOMS.get(id);
  const headers = new Headers(request.headers);
  headers.set('x-sudoku-player-id', current.id);
  headers.set('x-sudoku-room-id', roomId);
  return stub.fetch(new Request(request.url, { method: 'GET', headers }));
}

async function challengeById(env: Env, id: string): Promise<ChallengeRow> {
  const challenge = await env.DB.prepare('SELECT * FROM challenges WHERE id = ?')
    .bind(id)
    .first<ChallengeRow>();
  if (!challenge) throw new HttpError(404, 'Challenge not found.');
  return challenge;
}

async function challengeJson(env: Env, challenge: ChallengeRow): Promise<Record<string, unknown>> {
  const [challenger, recipient] = await Promise.all([
    env.DB.prepare('SELECT * FROM players WHERE id = ?')
      .bind(challenge.challenger_id)
      .first<PlayerRow>(),
    env.DB.prepare('SELECT * FROM players WHERE id = ?')
      .bind(challenge.recipient_id)
      .first<PlayerRow>(),
  ]);
  if (!challenger || !recipient) throw new HttpError(500, 'Challenge players are missing.');
  return {
    id: challenge.id,
    difficulty: challenge.difficulty,
    status: challenge.status,
    roomId: challenge.room_id,
    createdAt: challenge.created_at,
    expiresAt: challenge.expires_at,
    challenger: playerJson(challenger),
    recipient: playerJson(recipient),
  };
}

async function playerByPublicId(env: Env, publicId: string): Promise<PlayerRow> {
  const player = await env.DB.prepare('SELECT * FROM players WHERE public_id = ? LIMIT 1')
    .bind(publicId)
    .first<PlayerRow>();
  if (!player) throw new HttpError(404, 'Player not found.');
  return player;
}

function playerJson(player: PlayerRow): Record<string, unknown> {
  return {
    publicId: player.public_id,
    username: player.username,
    displayName: player.display_name,
    avatarKey: player.avatar_key,
    rating: player.rating,
    gamesPlayed: player.games_played,
    wins: player.wins,
    losses: player.losses,
    achievementCount: player.achievement_count,
    friendshipStatus: player.friendship_status ?? null,
    lastPlayedAt: player.last_played_at ?? null,
  };
}

async function enforceRateLimit(
  env: Env,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  const current = await env.DB.prepare(
    'SELECT window_started_at, count FROM request_limits WHERE key = ?',
  )
    .bind(key)
    .first<{ window_started_at: number; count: number }>();

  if (!current || now - current.window_started_at >= windowSeconds) {
    await env.DB.prepare(
      `INSERT INTO request_limits (key, window_started_at, count)
       VALUES (?, ?, 1)
       ON CONFLICT(key) DO UPDATE SET window_started_at = excluded.window_started_at, count = 1`,
    )
      .bind(key, now)
      .run();
    return;
  }
  if (current.count >= limit) throw new HttpError(429, 'Too many requests. Try again later.');
  await env.DB.prepare('UPDATE request_limits SET count = count + 1 WHERE key = ?')
    .bind(key)
    .run();
}

type PushMessage = {
  title: string;
  body: string;
  data: Record<string, string>;
};

async function sendPlayerNotification(
  env: Env,
  playerId: string,
  message: PushMessage,
): Promise<void> {
  if (
    !env.FCM_PROJECT_ID ||
    !env.FCM_CLIENT_EMAIL ||
    !env.FCM_PRIVATE_KEY ||
    env.FCM_PROJECT_ID.startsWith('REPLACE_')
  ) {
    console.warn('FCM secrets are not configured; challenge push skipped.');
    return;
  }

  const tokens = await env.DB.prepare(
    `SELECT id, token FROM device_tokens
     WHERE player_id = ? AND enabled = 1`,
  )
    .bind(playerId)
    .all<{ id: string; token: string }>();
  if (tokens.results.length === 0) return;

  const accessToken = await getFcmAccessToken(env);
  await Promise.all(
    tokens.results.map(async (device) => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FCM_PROJECT_ID)}/messages:send`,
        {
          method: 'POST',
          headers: {
            authorization: `Bearer ${accessToken}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: { title: message.title, body: message.body },
              data: message.data,
              android: {
                priority: 'high',
                notification: {
                  channel_id: 'online_challenges',
                  tag: `challenge_${message.data.challengeId ?? 'update'}`,
                  sound: 'default',
                },
              },
              apns: {
                headers: { 'apns-priority': '10' },
                payload: {
                  aps: {
                    sound: 'default',
                    badge: 1,
                    'thread-id': 'online-challenges',
                  },
                },
              },
            },
          }),
        },
      );

      if (!response.ok) {
        const text = await response.text();
        console.error('FCM send failed', response.status, text);
        if (text.includes('UNREGISTERED') || text.includes('registration-token-not-registered')) {
          await env.DB.prepare('UPDATE device_tokens SET enabled = 0 WHERE id = ?')
            .bind(device.id)
            .run();
        }
      }
    }),
  );
}

async function getFcmAccessToken(env: Env): Promise<string> {
  if (cachedFcmAccessToken && cachedFcmAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedFcmAccessToken.token;
  }

  const privateKey = env.FCM_PRIVATE_KEY.replace(/\\n/g, '\n');
  const key = await importPKCS8(privateKey, 'RS256');
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(env.FCM_CLIENT_EMAIL)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`FCM OAuth failed: ${await response.text()}`);
  const body = (await response.json()) as { access_token: string; expires_in: number };
  cachedFcmAccessToken = {
    token: body.access_token,
    expiresAt: Date.now() + body.expires_in * 1000,
  };
  return body.access_token;
}

function orderedPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a];
}

function normalizeUsername(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 32);
}

function sanitizeDisplayName(value: string): string {
  const clean = value.trim().replace(/[\u0000-\u001f\u007f]/g, '').slice(0, 30);
  return clean.length >= 2 ? clean : 'Sudoku Player';
}

function randomPublicId(): string {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (value) => value.toString(36).padStart(2, '0'))
    .join('')
    .toUpperCase();
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('Invalid object.');
    }
    return value as Record<string, unknown>;
  } catch {
    throw new HttpError(400, 'Invalid JSON body.');
  }
}

function requiredString(
  value: unknown,
  field: string,
  minLength: number,
  maxLength: number,
): string {
  if (typeof value !== 'string') throw new HttpError(400, `${field} is required.`);
  const clean = value.trim();
  if (clean.length < minLength || clean.length > maxLength) {
    throw new HttpError(400, `${field} has an invalid length.`);
  }
  return clean;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function reply(env: Env, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function errorReply(env: Env, status: number, error: string): Response {
  return reply(env, { error }, status);
}

function corsResponse(env: Env, response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set('access-control-allow-origin', env.ALLOWED_ORIGIN || '*');
  headers.set('access-control-allow-headers', 'authorization, content-type');
  headers.set('access-control-allow-methods', 'GET, POST, PUT, DELETE, OPTIONS');
  headers.set('vary', 'origin');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export class GameRoom {
  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
      return new Response('WebSocket upgrade required.', { status: 426 });
    }
    const playerId = request.headers.get('x-sudoku-player-id');
    const roomId = request.headers.get('x-sudoku-room-id');
    if (!playerId || !roomId) return new Response('Missing room identity.', { status: 400 });

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.state.acceptWebSocket(server, [playerId]);
    server.send(
      JSON.stringify({
        type: 'connected',
        roomId,
        playerId,
        serverTime: Date.now(),
      }),
    );
    this.broadcast({ type: 'presence', playerId, state: 'connected' }, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const [playerId] = this.state.getTags(socket);
    const text = typeof message === 'string' ? message : new TextDecoder().decode(message);
    if (text.length > 4096) {
      socket.close(1009, 'Message too large.');
      return;
    }
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(text) as Record<string, unknown>;
    } catch {
      socket.send(JSON.stringify({ type: 'error', error: 'Invalid JSON.' }));
      return;
    }
    const type = typeof parsed.type === 'string' ? parsed.type : '';
    if (!['ready', 'move', 'forfeit', 'ping'].includes(type)) {
      socket.send(JSON.stringify({ type: 'error', error: 'Unsupported message type.' }));
      return;
    }
    this.broadcast({
      ...parsed,
      playerId,
      serverTime: Date.now(),
    });
  }

  async webSocketClose(
    socket: WebSocket,
    code: number,
    reason: string,
    wasClean: boolean,
  ): Promise<void> {
    const [playerId] = this.state.getTags(socket);
    this.broadcast({
      type: 'presence',
      playerId,
      state: 'disconnected',
      code,
      wasClean,
    });
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    const [playerId] = this.state.getTags(socket);
    this.broadcast({ type: 'presence', playerId, state: 'error' });
  }

  private broadcast(payload: Record<string, unknown>, exclude?: WebSocket): void {
    const encoded = JSON.stringify(payload);
    for (const socket of this.state.getWebSockets()) {
      if (socket !== exclude) {
        try {
          socket.send(encoded);
        } catch {
          // The hibernation runtime removes closed sockets automatically.
        }
      }
    }
  }
}
