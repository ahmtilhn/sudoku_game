import {
  SignJWT,
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
} from 'jose';
import { AppCheckError, verifyAppCheckRequest } from './app_check';
import { coinBalance, ensureStarterGrant, entryFeeForDifficulty } from './economy';
import {
  nextAlarmAt,
  shouldPersistClientMessage,
  shouldUpdateAlarm,
  terminalRoomCleanupDue,
} from './cost_retention';
import {
  type ClientEnvelope,
  type DuelDifficulty,
  type DuelMode,
  type DuelState,
  type PlayerPublic,
  type PublicEvent,
  type Seat,
  applyDueDeadlines,
  applyForfeit,
  applyMove,
  applyRating,
  applyReady,
  applyScreenLoaded,
  createInitialDuelState,
  eloDelta,
  markConnected,
  markDisconnected,
  snapshot,
} from './online_duel';

export interface Env {
  DB: D1Database;
  GAME_ROOMS: DurableObjectNamespace;
  MATCHMAKING_QUEUE?: DurableObjectNamespace;
  FIREBASE_PROJECT_ID: string;
  FCM_PROJECT_ID: string;
  FCM_CLIENT_EMAIL: string;
  FCM_PRIVATE_KEY: string;
  ALLOWED_ORIGIN: string;
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
  BUILD_COMMIT?: string;
  ENVIRONMENT?: string;
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
      if (url.pathname === '/version') {
        return reply(env, {
          service: 'sudoku-duel-social',
          protocolVersion: 1,
          schemaVersion: 3,
          buildCommit: env.BUILD_COMMIT || 'local',
          environment: env.ENVIRONMENT || 'local',
        });
      }

      await verifyAppCheckRequest(request, env);
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
        /^\/v1\/challenges\/[^/]+$/.test(url.pathname) &&
        request.method === 'GET'
      ) {
        response = await getChallenge(env, player, url.pathname.split('/')[3]);
      } else if (
        /^\/v1\/challenges\/[^/]+$/.test(url.pathname) &&
        request.method === 'DELETE'
      ) {
        response = await cancelChallenge(env, ctx, player, url.pathname.split('/')[3]);
      } else if (
        url.pathname === '/v1/matchmaking/queue' &&
        request.method === 'POST'
      ) {
        response = await joinRankedQueue(request, env, player);
      } else if (
        url.pathname === '/v1/matchmaking/queue' &&
        request.method === 'DELETE'
      ) {
        response = await cancelRankedQueue(env, player);
      } else if (
        url.pathname === '/v1/matches/active' &&
        request.method === 'GET'
      ) {
        response = await activeMatch(env, player);
      } else if (
        url.pathname === '/v1/matches/history' &&
        request.method === 'GET'
      ) {
        response = await matchHistory(url, env, player);
      } else if (
        /^\/v1\/matches\/[^/]+$/.test(url.pathname) &&
        request.method === 'GET'
      ) {
        response = await matchDetail(env, player, url.pathname.split('/')[3]);
      } else if (url.pathname === '/v1/me/ratings' && request.method === 'GET') {
        response = await myRatings(env, player);
      } else if (
        /^\/v1\/leaderboards\/[^/]+$/.test(url.pathname) &&
        request.method === 'GET'
      ) {
        response = await leaderboard(url, env, player, url.pathname.split('/')[3]);
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
      if (error instanceof AppCheckError) {
        return corsResponse(env, errorReply(env, 403, error.code));
      }
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

async function getChallenge(
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

async function joinRankedQueue(
  request: Request,
  env: Env,
  current: PlayerRow,
): Promise<Response> {
  await enforceRateLimit(env, `ranked_queue:${current.id}`, 20, 600);
  const body = await readJson(request);
  const difficulty = requiredString(body.difficulty, 'difficulty', 4, 16);
  if (!DIFFICULTIES.has(difficulty)) throw new HttpError(400, 'Invalid difficulty.');
  const now = new Date().toISOString();
  const rating = await ratingFor(env, current.id, difficulty);
  const opponent = await env.DB.prepare(
    `SELECT q.player_id, q.rating, p.*
     FROM ranked_queue q
     JOIN players p ON p.id = q.player_id
     WHERE q.difficulty = ?
       AND q.player_id != ?
       AND NOT EXISTS (
         SELECT 1 FROM friendships b
         WHERE b.player_low_id = CASE WHEN q.player_id < ? THEN q.player_id ELSE ? END
           AND b.player_high_id = CASE WHEN q.player_id < ? THEN ? ELSE q.player_id END
           AND b.status = 'blocked'
       )
     ORDER BY ABS(q.rating - ?), q.joined_at
     LIMIT 1`,
  )
    .bind(difficulty, current.id, current.id, current.id, current.id, current.id, rating)
    .first<PlayerRow & { player_id: string; rating: number }>();

  if (!opponent) {
    await env.DB.prepare(
      `INSERT INTO ranked_queue (player_id, difficulty, rating, joined_at, updated_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(player_id) DO UPDATE SET
         difficulty = excluded.difficulty,
         rating = excluded.rating,
         updated_at = excluded.updated_at,
         room_id = NULL,
         matched_player_id = NULL`,
    )
      .bind(current.id, difficulty, rating, now, now)
      .run();
    return reply(env, { status: 'queued', difficulty, rating });
  }

  const roomId = crypto.randomUUID();
  await createMatchRow(env, {
    roomId,
    challengeId: null,
    mode: 'ranked',
    difficulty,
    playerAId: opponent.player_id,
    playerBId: current.id,
    now,
  });
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE ranked_queue
       SET room_id = ?, matched_player_id = ?, updated_at = ?
       WHERE player_id = ?`,
    ).bind(roomId, current.id, now, opponent.player_id),
    env.DB.prepare(
      `INSERT INTO ranked_queue (
         player_id, difficulty, rating, joined_at, updated_at, room_id, matched_player_id
       ) VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(player_id) DO UPDATE SET
         difficulty = excluded.difficulty,
         rating = excluded.rating,
         updated_at = excluded.updated_at,
         room_id = excluded.room_id,
         matched_player_id = excluded.matched_player_id`,
    ).bind(current.id, difficulty, rating, now, now, roomId, opponent.player_id),
  ]);
  return reply(env, { status: 'matched', difficulty, roomId }, 201);
}

async function cancelRankedQueue(env: Env, current: PlayerRow): Promise<Response> {
  await env.DB.prepare('DELETE FROM ranked_queue WHERE player_id = ? AND room_id IS NULL')
    .bind(current.id)
    .run();
  return reply(env, { ok: true });
}

async function activeMatch(env: Env, current: PlayerRow): Promise<Response> {
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

async function matchHistory(
  url: URL,
  env: Env,
  current: PlayerRow,
): Promise<Response> {
  const limit = clampLimit(url.searchParams.get('limit'), 20, 50);
  const rows = await env.DB.prepare(
    `SELECT m.*, mp.result, mp.score, mp.rating_delta_global
     FROM matches m
     JOIN match_players mp ON mp.match_id = m.id AND mp.player_id = ?
     WHERE m.player_a_id = ? OR m.player_b_id = ?
     ORDER BY COALESCE(m.finished_at, m.created_at) DESC
     LIMIT ?`,
  )
    .bind(current.id, current.id, current.id, limit)
    .all<Record<string, unknown>>();
  return reply(env, { matches: rows.results.map((row) => publicMatch(row, current.id)) });
}

async function matchDetail(
  env: Env,
  current: PlayerRow,
  matchId: string,
): Promise<Response> {
  const match = await env.DB.prepare(
    `SELECT * FROM matches
     WHERE id = ? AND (player_a_id = ? OR player_b_id = ?)
     LIMIT 1`,
  )
    .bind(matchId, current.id, current.id)
    .first<Record<string, unknown>>();
  if (!match) throw new HttpError(404, 'Match not found.');
  const players = await env.DB.prepare(
    'SELECT * FROM match_players WHERE match_id = ? ORDER BY seat',
  )
    .bind(matchId)
    .all<Record<string, unknown>>();
  return reply(env, { match: publicMatch(match, current.id), players: players.results });
}

async function myRatings(env: Env, current: PlayerRow): Promise<Response> {
  await ensureRatingRows(env, current.id);
  const rows = await env.DB.prepare(
    `SELECT scope, rating, games_played, wins, losses, draws, best_rating, provisional_games
     FROM player_ratings WHERE player_id = ? ORDER BY scope`,
  )
    .bind(current.id)
    .all<Record<string, unknown>>();
  return reply(env, { ratings: rows.results });
}

async function leaderboard(
  url: URL,
  env: Env,
  current: PlayerRow,
  scope: string,
): Promise<Response> {
  if (scope !== 'global' && !DIFFICULTIES.has(scope)) {
    throw new HttpError(400, 'Invalid leaderboard scope.');
  }
  const limit = clampLimit(url.searchParams.get('limit'), 50, 100);
  const rows = await env.DB.prepare(
    `SELECT pr.*, p.public_id, p.username, p.display_name, p.avatar_key
     FROM player_ratings pr
     JOIN players p ON p.id = pr.player_id
     WHERE pr.scope = ?
     ORDER BY pr.rating DESC, pr.games_played DESC, pr.updated_at ASC
     LIMIT ?`,
  )
    .bind(scope, limit)
    .all<Record<string, unknown>>();
  const rank = await env.DB.prepare(
    `SELECT COUNT(*) + 1 AS rank
     FROM player_ratings mine
     JOIN player_ratings other ON other.scope = mine.scope
     WHERE mine.player_id = ? AND mine.scope = ?
       AND (other.rating > mine.rating
         OR (other.rating = mine.rating AND other.games_played > mine.games_played)
         OR (other.rating = mine.rating AND other.games_played = mine.games_played
             AND other.updated_at < mine.updated_at))`,
  )
    .bind(current.id, scope)
    .first<{ rank: number }>();
  const currentRating = await ratingFor(env, current.id, scope);
  return reply(env, {
    scope,
    entries: rows.results.map((row, index) => ({
      rank: index + 1,
      publicId: row.public_id,
      username: row.username,
      displayName: row.display_name,
      avatarKey: row.avatar_key,
      rating: row.rating,
      gamesPlayed: row.games_played,
      wins: row.wins,
      losses: row.losses,
      draws: row.draws,
      winRate:
        Number(row.games_played) === 0
          ? 0
          : Number(row.wins) / Number(row.games_played),
    })),
    currentPlayer: { rank: rank?.rank ?? null, rating: currentRating },
    nextCursor: null,
  });
}

async function ensureAcceptedChallengeMatch(
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

async function createMatchRow(
  env: Env,
  input: {
    roomId: string;
    challengeId: string | null;
    mode: DuelMode;
    difficulty: string;
    playerAId: string;
    playerBId: string;
    now: string;
  },
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO matches (
      id, room_id, challenge_id, mode, difficulty, status,
      player_a_id, player_b_id, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, 'waiting', ?, ?, ?, ?)
    ON CONFLICT(room_id) DO NOTHING`,
  )
    .bind(
      crypto.randomUUID(),
      input.roomId,
      input.challengeId,
      input.mode,
      input.difficulty,
      input.playerAId,
      input.playerBId,
      input.now,
      input.now,
    )
    .run();
}

async function ensureRatingRows(env: Env, playerId: string): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.batch(
    ['global', ...DIFFICULTIES].map((scope) =>
      env.DB.prepare(
        `INSERT INTO player_ratings (player_id, scope, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(player_id, scope) DO NOTHING`,
      ).bind(playerId, scope, now),
    ),
  );
}

async function ratingFor(env: Env, playerId: string, scope: string): Promise<number> {
  await ensureRatingRows(env, playerId);
  const row = await env.DB.prepare(
    'SELECT rating FROM player_ratings WHERE player_id = ? AND scope = ?',
  )
    .bind(playerId, scope)
    .first<{ rating: number }>();
  return row?.rating ?? 1000;
}

function clampLimit(value: string | null, fallback: number, max: number): number {
  const parsed = Number(value ?? fallback);
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback;
  return Math.min(parsed, max);
}

function publicMatch(row: Record<string, unknown>, currentPlayerId: string): Record<string, unknown> {
  const playerAId = String(row.player_a_id ?? '');
  const playerBId = String(row.player_b_id ?? '');
  return {
    id: row.id,
    roomId: row.room_id,
    mode: row.mode,
    difficulty: row.difficulty,
    challengeId: row.challenge_id ?? null,
    status: row.status,
    youSeat: currentPlayerId === playerAId ? 'A' : currentPlayerId === playerBId ? 'B' : null,
    winnerSeat:
      row.winner_id == null
        ? null
        : row.winner_id === playerAId
          ? 'A'
          : row.winner_id === playerBId
            ? 'B'
            : null,
    finishReason: row.finish_reason,
    startedAt: row.started_at,
    finishedAt: row.finished_at,
    result: row.result ?? null,
    score: row.score ?? null,
    ratingDelta: row.rating_delta_global ?? null,
  };
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
  const match = await env.DB.prepare(
    `SELECT * FROM matches
     WHERE room_id = ?
       AND status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')
     LIMIT 1`,
  )
    .bind(roomId)
    .first<{
      player_a_id: string;
      player_b_id: string;
    }>();
  if (!match) throw new HttpError(404, 'Game room not found.');
  if (match.player_a_id !== current.id && match.player_b_id !== current.id) {
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
  private roomState: DuelState | null = null;
  private persistedMatchStatus: string | null = null;

  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {
    this.state.blockConcurrencyWhile(async () => {
      this.roomState = (await this.state.storage.get<DuelState>('duelState')) ?? null;
    });
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
      return new Response('WebSocket upgrade required.', { status: 426 });
    }
    const playerId = request.headers.get('x-sudoku-player-id');
    const roomId = request.headers.get('x-sudoku-room-id');
    if (!playerId || !roomId) return new Response('Missing room identity.', { status: 400 });

    const duel = await this.loadOrCreate(roomId);
    const seat = this.seatForPlayer(duel, playerId);
    if (!seat) return new Response('Forbidden.', { status: 403 });
    const replacedSockets = this.state.getWebSockets(playerId);
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.state.acceptWebSocket(server, [playerId]);

    for (const socket of replacedSockets) {
      try {
        socket.close(4001, 'Replaced by a newer connection.');
      } catch {
        // Closed sockets are ignored by the hibernation runtime.
      }
    }
    const now = Date.now();
    const events = applyDueDeadlines(duel, now);
    events.push(markConnected(duel, seat, now));
    await this.persist();
    this.send(server, {
      v: 1,
      type: 'connected',
      eventId: `${duel.roomId}:${duel.revision}:connected:${seat}`,
      revision: duel.revision,
      serverTime: now,
      payload: snapshot(duel, seat, now),
    });
    this.broadcast(events);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const [playerId] = this.state.getTags(socket);
    const text = typeof message === 'string' ? message : new TextDecoder().decode(message);
    if (text.length > 4096) {
      socket.close(1009, 'Message too large.');
      return;
    }
    const duel = this.roomState;
    if (!duel) {
      this.send(socket, serverError(0, 'room_not_initialized'));
      return;
    }
    const seat = this.seatForPlayer(duel, playerId);
    if (!seat) {
      socket.close(4003, 'Forbidden.');
      return;
    }
    let parsed: ClientEnvelope;
    try {
      parsed = JSON.parse(text) as ClientEnvelope;
    } catch {
      this.send(socket, protocolError(duel, 'invalid_json'));
      return;
    }
    if (parsed.v !== 1 || typeof parsed.type !== 'string') {
      this.send(socket, protocolError(duel, 'invalid_envelope'));
      return;
    }
    const now = Date.now();
    const requestId = requestIdOf(parsed);
    const beforeRevision = duel.revision;
    let events: PublicEvent[];
    if (parsed.type === 'ready') {
      events = applyReady(duel, seat, now);
    } else if (parsed.type === 'game_screen_loaded' || parsed.type === 'screen_loaded') {
      events = applyScreenLoaded(duel, seat, now);
    } else if (parsed.type === 'move') {
      const payload = parsed.payload ?? {};
      events = applyMove(
        duel,
        seat,
        requestId,
        parsed.expectedRevision,
        Number(payload.cellIndex),
        Number(payload.value),
        now,
      );
    } else if (parsed.type === 'forfeit') {
      events = applyForfeit(duel, seat, requestId, now);
    } else if (parsed.type === 'request_snapshot') {
      events = [
        {
          v: 1,
          type: 'snapshot',
          eventId: `${duel.roomId}:${duel.revision}:snapshot:${seat}`,
          revision: duel.revision,
          serverTime: now,
          payload: snapshot(duel, seat, now),
        },
      ];
    } else if (parsed.type === 'ping') {
      events = [
        {
          v: 1,
          type: 'pong',
          eventId: `${duel.roomId}:${duel.revision}:pong:${seat}`,
          revision: duel.revision,
          serverTime: now,
          payload: {},
        },
      ];
    } else {
      events = [protocolError(duel, 'unsupported_message_type')];
    }
    if (
      shouldPersistClientMessage({
        type: parsed.type,
        beforeRevision,
        afterRevision: duel.revision,
      })
    ) {
      await this.persist();
    }
    this.broadcast(events);
    if (duel.status === 'completed' || duel.status === 'forfeited' || duel.status === 'cancelled') {
      await this.settleIfNeeded(duel);
    }
  }

  async webSocketClose(
    socket: WebSocket,
    code: number,
    reason: string,
    wasClean: boolean,
  ): Promise<void> {
    const [playerId] = this.state.getTags(socket);
    const duel = this.roomState;
    if (!duel) return;
    const seat = this.seatForPlayer(duel, playerId);
    if (!seat) return;
    const hasReplacementSocket = this.state
      .getWebSockets(playerId)
      .some((candidate) => candidate !== socket && candidate.readyState === 1);
    if (hasReplacementSocket) return;
    const event = markDisconnected(duel, seat, Date.now());
    await this.persist();
    this.broadcast([event]);
    await this.scheduleAlarm();
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    const [playerId] = this.state.getTags(socket);
    console.warn('room websocket error', { playerId });
  }

  async alarm(): Promise<void> {
    const duel = this.roomState;
    if (!duel) return;
    const now = Date.now();
    if (
      terminalRoomCleanupDue(
        { status: duel.status, settled: duel.settled, finishedAt: duel.finishedAt },
        now,
      )
    ) {
      await this.cleanupTerminalRoom();
      return;
    }
    const events = applyDueDeadlines(duel, now);
    if (events.length > 0) {
      await this.persist();
      this.broadcast(events);
    }
    if (duel.status === 'completed' || duel.status === 'forfeited' || duel.status === 'cancelled') {
      await this.settleIfNeeded(duel);
    }
    await this.scheduleAlarm();
  }

  private async loadOrCreate(roomId: string): Promise<DuelState> {
    if (this.roomState) return this.roomState;
    const match = await this.env.DB.prepare(
      `SELECT m.*, a.public_id AS a_public_id, a.username AS a_username,
              a.display_name AS a_display_name, a.avatar_key AS a_avatar_key,
              b.public_id AS b_public_id, b.username AS b_username,
              b.display_name AS b_display_name, b.avatar_key AS b_avatar_key
       FROM matches m
       JOIN players a ON a.id = m.player_a_id
       JOIN players b ON b.id = m.player_b_id
       WHERE m.room_id = ?
         AND m.status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')
       LIMIT 1`,
    )
      .bind(roomId)
      .first<Record<string, string>>();
    if (!match) throw new Error('Match row not found.');
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    const now = Date.now();
    this.roomState = createInitialDuelState({
      roomId,
      matchId: match.id,
      challengeId: match.challenge_id ?? null,
      mode: match.mode as DuelMode,
      difficulty: match.difficulty as DuelDifficulty,
      playerA: publicPlayer(match.player_a_id, match.a_public_id, match.a_username, match.a_display_name, match.a_avatar_key),
      playerB: publicPlayer(match.player_b_id, match.b_public_id, match.b_username, match.b_display_name, match.b_avatar_key),
      now,
      randomBytes: bytes,
    });
    await this.persist();
    return this.roomState;
  }

  private seatForPlayer(duel: DuelState, playerId: string): Seat | null {
    if (duel.playerA.player.id === playerId) return 'A';
    if (duel.playerB.player.id === playerId) return 'B';
    return null;
  }

  private async persist(): Promise<void> {
    if (!this.roomState) return;
    await this.state.storage.put('duelState', this.roomState);
    const activeStatuses = new Set(['waiting', 'ready_window', 'countdown', 'active', 'paused']);
    if (
      activeStatuses.has(this.roomState.status) &&
      this.persistedMatchStatus !== this.roomState.status
    ) {
      await this.env.DB.prepare(
        `UPDATE matches SET status = ?, updated_at = ? WHERE id = ?`,
      )
        .bind(this.roomState.status, new Date().toISOString(), this.roomState.matchId)
        .run();
      this.persistedMatchStatus = this.roomState.status;
    }
    await this.scheduleAlarm();
  }

  private async scheduleAlarm(): Promise<void> {
    const duel = this.roomState;
    if (!duel) return;
    const desiredAlarmAt = nextAlarmAt(
      {
        status: duel.status,
        lobbyDeadline: duel.lobbyDeadline ?? null,
        readyDeadline: duel.readyDeadline,
        turnDeadline: duel.turnDeadline,
        playerADisconnectDeadline: duel.playerA.disconnectDeadline,
        playerBDisconnectDeadline: duel.playerB.disconnectDeadline,
        finishedAt: duel.finishedAt,
        settled: duel.settled,
      },
      Date.now(),
    );
    const currentAlarmAt = await this.state.storage.getAlarm();
    if (!shouldUpdateAlarm(currentAlarmAt, desiredAlarmAt)) return;
    if (desiredAlarmAt === null) {
      await this.state.storage.deleteAlarm();
    } else {
      await this.state.storage.setAlarm(desiredAlarmAt);
    }
  }

  private async settleIfNeeded(duel: DuelState): Promise<void> {
    if (duel.settled) return;
    const existingSettlement = await this.env.DB.prepare(
      'SELECT 1 FROM match_settlements WHERE match_id = ? LIMIT 1',
    )
      .bind(duel.matchId)
      .first();
    if (existingSettlement) {
      duel.settled = true;
      await this.persist();
      return;
    }
    duel.settlementAttempts++;
    const now = new Date().toISOString();
    const winnerId =
      duel.winnerSeat === 'A'
        ? duel.playerA.player.id
        : duel.winnerSeat === 'B'
          ? duel.playerB.player.id
          : null;
    const rated = duel.mode === 'ranked' && duel.startedAt !== null && duel.status !== 'cancelled';
    const globalA = await this.ratingRow(duel.playerA.player.id, 'global');
    const globalB = await this.ratingRow(duel.playerB.player.id, 'global');
    const diffA = await this.ratingRow(duel.playerA.player.id, duel.difficulty);
    const diffB = await this.ratingRow(duel.playerB.player.id, duel.difficulty);
    let resultA: 0 | 0.5 | 1 = 0.5;
    if (duel.winnerSeat === 'A') resultA = 1;
    if (duel.winnerSeat === 'B') resultA = 0;
    const resultB = (1 - resultA) as 0 | 0.5 | 1;
    const globalDeltaA = rated ? eloDelta(globalA.rating, globalB.rating, resultA, globalA.games_played) : 0;
    const globalDeltaB = rated ? eloDelta(globalB.rating, globalA.rating, resultB, globalB.games_played) : 0;
    const diffDeltaA = rated ? eloDelta(diffA.rating, diffB.rating, resultA, diffA.games_played) : 0;
    const diffDeltaB = rated ? eloDelta(diffB.rating, diffA.rating, resultB, diffB.games_played) : 0;
    duel.ratingResult = {
      A: {
        beforeGlobal: globalA.rating,
        afterGlobal: applyRating(globalA.rating, globalDeltaA),
        deltaGlobal: globalDeltaA,
        beforeDifficulty: diffA.rating,
        afterDifficulty: applyRating(diffA.rating, diffDeltaA),
        deltaDifficulty: diffDeltaA,
      },
      B: {
        beforeGlobal: globalB.rating,
        afterGlobal: applyRating(globalB.rating, globalDeltaB),
        deltaGlobal: globalDeltaB,
        beforeDifficulty: diffB.rating,
        afterDifficulty: applyRating(diffB.rating, diffDeltaB),
        deltaDifficulty: diffDeltaB,
      },
    };
    const escrow = await this.env.DB.prepare(
      `SELECT player_a_amount, player_b_amount, pot_amount
       FROM match_coin_escrow
       WHERE match_id = ? LIMIT 1`,
    )
      .bind(duel.matchId)
      .first<{
        player_a_amount: number;
        player_b_amount: number;
        pot_amount: number;
      }>();
    const coinAmount = Number(escrow?.pot_amount ?? 0);
    const coinStatements: D1PreparedStatement[] = [];
    if (duel.winnerSeat !== null && duel.status !== 'cancelled' && coinAmount > 0) {
      const loserSeat = duel.winnerSeat === 'A' ? 'B' : 'A';
      const loserId = loserSeat === 'A' ? duel.playerA.player.id : duel.playerB.player.id;
      coinStatements.push(
        this.env.DB.prepare(
          `INSERT INTO match_coin_settlements (match_id, winner_id, loser_id, amount, applied_at)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(match_id) DO NOTHING`,
        ).bind(duel.matchId, winnerId, loserId, coinAmount, now),
      );
    }
    const settlementHash = `${duel.matchId}:${duel.revision}:${duel.finishReason}:${winnerId ?? 'draw'}`;
    await this.env.DB.batch([
      this.env.DB.prepare(
        `INSERT INTO match_settlements (match_id, settlement_hash, settled_at, attempts)
         VALUES (?, ?, ?, 1)
         ON CONFLICT(match_id) DO UPDATE SET attempts = attempts + 1`,
      ).bind(duel.matchId, settlementHash, now),
      this.env.DB.prepare(
        `UPDATE matches
         SET status = ?, finished_at = ?, winner_id = ?, finish_reason = ?,
             rated = ?, rating_settled_at = ?, updated_at = ?
         WHERE id = ? AND rating_settled_at IS NULL`,
      ).bind(duel.status, now, winnerId, duel.finishReason, rated ? 1 : 0, now, now, duel.matchId),
      this.matchPlayerStatement(duel, 'A', resultA, duel.ratingResult.A, now),
      this.matchPlayerStatement(duel, 'B', resultB, duel.ratingResult.B, now),
      ...(duel.startedAt !== null
        ? [
            this.env.DB.prepare(
              `INSERT INTO recent_opponents (
                 player_low_id, player_high_id, last_challenge_id, last_winner_id, last_played_at
               ) VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(player_low_id, player_high_id) DO UPDATE SET
                 last_challenge_id = excluded.last_challenge_id,
                 last_winner_id = excluded.last_winner_id,
                 last_played_at = excluded.last_played_at`,
            ).bind(
              ...orderedPair(duel.playerA.player.id, duel.playerB.player.id),
              duel.challengeId,
              winnerId,
              now,
            ),
          ]
        : []),
      ...this.ratingStatements(duel, 'A', resultA, duel.ratingResult.A, rated, now),
      ...this.ratingStatements(duel, 'B', resultB, duel.ratingResult.B, rated, now),
      this.env.DB.prepare(
        'UPDATE challenges SET status = ? WHERE id = ? AND status = ?',
      ).bind(duel.status === 'cancelled' ? 'cancelled' : 'completed', duel.challengeId, 'accepted'),
      ...coinStatements,
    ]);
    if (duel.winnerSeat !== null && duel.status !== 'cancelled' && coinAmount > 0) {
      const loserSeat = duel.winnerSeat === 'A' ? 'B' : 'A';
      const winnerBalance = await this.onlineCoinBalance(duel.winnerSeat === 'A' ? duel.playerA.player.id : duel.playerB.player.id);
      const loserBalance = await this.onlineCoinBalance(loserSeat === 'A' ? duel.playerA.player.id : duel.playerB.player.id);
      duel.coinResult = {
        amount: coinAmount,
        winnerSeat: duel.winnerSeat,
        loserSeat,
        balances: {
          [duel.winnerSeat]: winnerBalance,
          [loserSeat]: loserBalance,
        } as Record<Seat, number>,
        deltas: {
          [duel.winnerSeat]: coinAmount,
          [loserSeat]: 0,
        } as Record<Seat, number>,
      };
      await this.env.DB.prepare(
        `UPDATE match_coin_settlements
         SET winner_balance_after = ?, loser_balance_after = ?
         WHERE match_id = ?`,
      ).bind(winnerBalance, loserBalance, duel.matchId).run();
    } else if (duel.winnerSeat === null && escrow) {
      const balanceA = await this.onlineCoinBalance(duel.playerA.player.id);
      const balanceB = await this.onlineCoinBalance(duel.playerB.player.id);
      duel.coinResult = {
        amount: 0,
        winnerSeat: null,
        loserSeat: null,
        balances: { A: balanceA, B: balanceB },
        deltas: {
          A: Number(escrow.player_a_amount ?? 0),
          B: Number(escrow.player_b_amount ?? 0),
        },
      };
    }
    duel.settled = true;
    await this.persist();
    this.broadcast([
      {
        v: 1,
        type: 'rating_updated',
        eventId: `${duel.roomId}:${duel.revision}:rating_updated`,
        revision: duel.revision,
        serverTime: Date.now(),
        payload: { rating: duel.ratingResult, coinSettlement: duel.coinResult },
      },
    ]);
  }

  private async cleanupTerminalRoom(): Promise<void> {
    for (const socket of this.state.getWebSockets()) {
      try {
        socket.close(1000, 'Match storage cleaned up.');
      } catch {
        // Closed sockets are ignored by the hibernation runtime.
      }
    }
    this.roomState = null;
    await this.state.storage.deleteAlarm();
    await this.state.storage.deleteAll();
  }

  private async onlineCoinBalance(playerId: string): Promise<number> {
    const row = await this.env.DB.prepare('SELECT online_coins FROM players WHERE id = ?')
      .bind(playerId)
      .first<{ online_coins: number }>();
    return row?.online_coins ?? 0;
  }

  private async ratingRow(playerId: string, scope: string): Promise<{ rating: number; games_played: number }> {
    await ensureRatingRows(this.env, playerId);
    const row = await this.env.DB.prepare(
      'SELECT rating, games_played FROM player_ratings WHERE player_id = ? AND scope = ?',
    )
      .bind(playerId, scope)
      .first<{ rating: number; games_played: number }>();
    return row ?? { rating: 1000, games_played: 0 };
  }

  private matchPlayerStatement(
    duel: DuelState,
    seat: Seat,
    result: 0 | 0.5 | 1,
    rating: NonNullable<DuelState['ratingResult']>[Seat],
    now: string,
  ): D1PreparedStatement {
    const playerId = seat === 'A' ? duel.playerA.player.id : duel.playerB.player.id;
    const resultText = duel.status === 'cancelled' ? 'cancelled' : result === 1 ? 'win' : result === 0 ? 'loss' : 'draw';
    return this.env.DB.prepare(
      `INSERT INTO match_players (
        match_id, player_id, seat, result, score, mistakes, correct_moves,
        timeouts, rating_before_global, rating_after_global, rating_delta_global,
        rating_before_difficulty, rating_after_difficulty, rating_delta_difficulty, joined_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(match_id, player_id) DO NOTHING`,
    ).bind(
      duel.matchId,
      playerId,
      seat,
      resultText,
      duel.scores[seat],
      duel.mistakes[seat],
      duel.correctMoves[seat],
      duel.timeouts[seat],
      rating.beforeGlobal,
      rating.afterGlobal,
      rating.deltaGlobal,
      rating.beforeDifficulty,
      rating.afterDifficulty,
      rating.deltaDifficulty,
      now,
    );
  }

  private ratingStatements(
    duel: DuelState,
    seat: Seat,
    result: 0 | 0.5 | 1,
    rating: NonNullable<DuelState['ratingResult']>[Seat],
    rated: boolean,
    now: string,
  ): D1PreparedStatement[] {
    if (!rated) return [];
    const playerId = seat === 'A' ? duel.playerA.player.id : duel.playerB.player.id;
    const win = result === 1 ? 1 : 0;
    const loss = result === 0 ? 1 : 0;
    const draw = result === 0.5 ? 1 : 0;
    return [
      this.env.DB.prepare(
        `UPDATE player_ratings
         SET rating = ?, games_played = games_played + 1, wins = wins + ?,
             losses = losses + ?, draws = draws + ?,
             win_streak = CASE WHEN ? = 1 THEN win_streak + 1 ELSE 0 END,
             best_rating = MAX(best_rating, ?), provisional_games = MAX(0, provisional_games - 1),
             updated_at = ?
         WHERE player_id = ? AND scope = 'global'`,
      ).bind(rating.afterGlobal, win, loss, draw, win, rating.afterGlobal, now, playerId),
      this.env.DB.prepare(
        `UPDATE player_ratings
         SET rating = ?, games_played = games_played + 1, wins = wins + ?,
             losses = losses + ?, draws = draws + ?,
             win_streak = CASE WHEN ? = 1 THEN win_streak + 1 ELSE 0 END,
             best_rating = MAX(best_rating, ?), provisional_games = MAX(0, provisional_games - 1),
             updated_at = ?
         WHERE player_id = ? AND scope = ?`,
      ).bind(rating.afterDifficulty, win, loss, draw, win, rating.afterDifficulty, now, playerId, duel.difficulty),
      this.env.DB.prepare('UPDATE players SET rating = ?, games_played = games_played + 1, wins = wins + ?, losses = losses + ? WHERE id = ?')
        .bind(rating.afterGlobal, win, loss, playerId),
    ];
  }

  private broadcast(events: PublicEvent[]): void {
    if (events.length === 0) return;
    for (const socket of this.state.getWebSockets()) {
      for (const payload of events) {
        this.send(socket, this.eventForSocket(socket, payload));
      }
    }
  }

  private eventForSocket(
    socket: WebSocket,
    payload: PublicEvent,
  ): PublicEvent {
    const duel = this.roomState;
    if (!duel) return payload;

    const [playerId] = this.state.getTags(socket);
    const seat = this.seatForPlayer(duel, playerId);
    if (!seat) return payload;

    if (
      payload.type === 'match_started' ||
      payload.type === 'game_started' ||
      payload.type === 'snapshot'
    ) {
      return {
        ...payload,
        payload: snapshot(duel, seat, payload.serverTime),
      };
    }

    const actorSeat = payload.payload.seat;
    if (
      (payload.type === 'move_accepted' ||
        payload.type === 'move_rejected') &&
      (actorSeat === 'A' || actorSeat === 'B')
    ) {
      const recovery = payload.payload.snapshot;
      return {
        ...payload,
        payload: {
          ...payload.payload,
          forYou: actorSeat === seat,
          ...(recovery && typeof recovery === 'object'
            ? { snapshot: snapshot(duel, seat, payload.serverTime) }
            : {}),
        },
      };
    }

    return payload;
  }

  private send(socket: WebSocket, payload: PublicEvent): void {
    try {
      socket.send(JSON.stringify(payload));
    } catch {
      // The hibernation runtime removes closed sockets automatically.
    }
  }
}

export class MatchmakingQueue {
  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {}

  fetch(): Response {
    return new Response('Matchmaking queue is coordinated through the authenticated Worker API.', {
      status: 200,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    });
  }
}

function requestIdOf(envelope: ClientEnvelope): string {
  return typeof envelope.requestId === 'string' && envelope.requestId.length <= 80
    ? envelope.requestId
    : crypto.randomUUID();
}

function protocolError(state: DuelState, code: string): PublicEvent {
  return {
    v: 1,
    type: 'protocol_error',
    eventId: `${state.roomId}:${state.revision}:protocol_error:${code}`,
    revision: state.revision,
    serverTime: Date.now(),
    payload: { code },
  };
}

function serverError(revision: number, code: string): PublicEvent {
  return {
    v: 1,
    type: 'server_error',
    eventId: `server:${revision}:${code}`,
    revision,
    serverTime: Date.now(),
    payload: { code },
  };
}

function publicPlayer(
  id: string,
  publicId: string,
  username: string,
  displayName: string,
  avatarKey: string,
): PlayerPublic {
  return { id, publicId, username, displayName, avatarKey };
}
