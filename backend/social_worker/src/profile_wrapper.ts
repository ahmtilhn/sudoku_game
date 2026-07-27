import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';
import app, { GameRoom, MatchmakingQueue } from './main';
import type { Env } from './index';

export { GameRoom, MatchmakingQueue };

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

const RESERVED_USERNAMES = new Set([
  'admin',
  'administrator',
  'moderator',
  'support',
  'sudoku',
  'sudokuduel',
  'devovia',
  'official',
  'system',
]);

const UNSAFE_PARTS = [
  'fuck',
  'shit',
  'nazi',
  'hitler',
  'porn',
  'sex',
];

type RuntimeEnv = Env & {
  ALLOW_TEST_PURCHASE_GRANTS?: string;
};

type ProfileRow = {
  id: string;
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
  profile_confirmed: number;
  discoverable: number;
  name_source: string;
};

export default {
  async fetch(
    request: Request,
    env: RuntimeEnv,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/v1/me/preferences') {
      return handlePreferences(request, env, ctx);
    }

    if (url.pathname === '/v1/players/search' && request.method === 'GET') {
      return searchDiscoverablePlayers(request, env, ctx, url);
    }

    if (url.pathname === '/v1/me' && request.method === 'POST') {
      const response = await app.fetch(request, env, ctx);
      if (!response.ok) return response;
      try {
        const uid = await authenticateFirebase(request, env);
        const row = await playerForUid(env, uid);
        if (!row) return response;
        const original = (await response.json()) as Record<string, unknown>;
        return json(env, 200, {
          ...original,
          profileConfirmed: row.profile_confirmed === 1,
          discoverable: row.discoverable === 1,
          nameSource: row.name_source,
        });
      } catch {
        return response;
      }
    }

    return app.fetch(request, env, ctx);
  },
};

async function handlePreferences(
  request: Request,
  env: RuntimeEnv,
  ctx: ExecutionContext,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    let player = await playerForUid(env, uid);
    if (!player) {
      const profileRequest = new Request(new URL('/v1/me', request.url), {
        method: 'POST',
        headers: request.headers,
        body: '{}',
      });
      const created = await app.fetch(profileRequest, env, ctx);
      if (!created.ok) return created;
      player = await playerForUid(env, uid);
    }
    if (!player) return json(env, 500, { error: 'Unable to load player profile.' });

    if (request.method === 'GET') {
      return json(env, 200, profileJson(player));
    }
    if (request.method !== 'PUT') {
      return json(env, 405, { error: 'Method not allowed.' });
    }

    const body = await readJson(request);
    const displayName = sanitizeDisplayName(
      typeof body.displayName === 'string' ? body.displayName : player.display_name,
    );
    const requestedUsername = typeof body.username === 'string'
      ? body.username
      : player.username;
    const username = normalizeUsername(requestedUsername);
    validateUsername(username);
    const discoverable = body.discoverable == null
      ? player.discoverable === 1
      : body.discoverable === true;
    const nameSource = normalizeNameSource(body.nameSource, player.name_source);

    const conflict = await env.DB.prepare(
      `SELECT id FROM players
       WHERE username_normalized = ? AND id != ?
       LIMIT 1`,
    )
      .bind(username, player.id)
      .first<{ id: string }>();
    if (conflict) {
      return json(env, 409, {
        error: 'This username is already in use.',
        code: 'username_taken',
      });
    }

    const now = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE players
       SET username = ?, username_normalized = ?, display_name = ?,
           discoverable = ?, profile_confirmed = 1, name_source = ?,
           updated_at = ?, last_seen_at = ?
       WHERE id = ?`,
    )
      .bind(
        username,
        username,
        displayName,
        discoverable ? 1 : 0,
        nameSource,
        now,
        now,
        player.id,
      )
      .run();

    const updated = await env.DB.prepare('SELECT * FROM players WHERE id = ?')
      .bind(player.id)
      .first<ProfileRow>();
    return json(env, 200, profileJson(updated ?? player));
  } catch (error) {
    return routeError(env, error);
  }
}

async function searchDiscoverablePlayers(
  request: Request,
  env: RuntimeEnv,
  ctx: ExecutionContext,
  url: URL,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    let current = await playerForUid(env, uid);
    if (!current) {
      const created = await app.fetch(
        new Request(new URL('/v1/me', request.url), {
          method: 'POST',
          headers: request.headers,
          body: '{}',
        }),
        env,
        ctx,
      );
      if (!created.ok) return created;
      current = await playerForUid(env, uid);
    }
    if (!current) return json(env, 500, { error: 'Unable to load player profile.' });

    const raw = (url.searchParams.get('q') ?? '').trim();
    if (raw.length < 3 || raw.length > 64) return json(env, 200, { players: [] });
    const normalized = normalizeUsername(raw);
    const pattern = `%${normalized}%`;
    const displayPattern = `%${raw.toLowerCase()}%`;

    const rows = await env.DB.prepare(
      `SELECT p.*,
         CASE
           WHEN f.status IS NULL THEN NULL
           WHEN f.status = 'accepted' THEN 'accepted'
           WHEN f.requester_id = ? THEN 'outgoing_pending'
           ELSE 'incoming_pending'
         END AS friendship_status
       FROM players p
       LEFT JOIN friendships f
         ON f.player_low_id = CASE WHEN p.id < ? THEN p.id ELSE ? END
        AND f.player_high_id = CASE WHEN p.id < ? THEN ? ELSE p.id END
        AND f.status != 'blocked'
       WHERE p.id != ?
         AND p.discoverable = 1
         AND (
           p.public_id = upper(?)
           OR p.username_normalized LIKE ?
           OR lower(p.display_name) LIKE ?
         )
       ORDER BY
         CASE WHEN p.public_id = upper(?) THEN 0 ELSE 1 END,
         p.rating DESC,
         p.username_normalized
       LIMIT 40`,
    )
      .bind(
        current.id,
        current.id,
        current.id,
        current.id,
        current.id,
        current.id,
        raw,
        pattern,
        displayPattern,
        raw,
      )
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
        friendshipStatus: row.friendship_status,
      })),
    });
  } catch (error) {
    return routeError(env, error);
  }
}

async function playerForUid(env: RuntimeEnv, uid: string): Promise<ProfileRow | null> {
  return env.DB.prepare('SELECT * FROM players WHERE firebase_uid = ? LIMIT 1')
    .bind(uid)
    .first<ProfileRow>();
}

async function authenticateFirebase(
  request: Request,
  env: RuntimeEnv,
): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) throw new ProfileError(401, 'Missing bearer token.');
  const token = header.slice(7).trim();
  if (!token) throw new ProfileError(401, 'Missing bearer token.');
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
    throw new ProfileError(401, 'Invalid or expired Firebase ID token.');
  }
}

function profileJson(row: ProfileRow): Record<string, unknown> {
  return {
    publicId: row.public_id,
    username: row.username,
    displayName: row.display_name,
    avatarKey: row.avatar_key,
    rating: row.rating,
    gamesPlayed: row.games_played,
    wins: row.wins,
    losses: row.losses,
    achievementCount: row.achievement_count,
    profileConfirmed: row.profile_confirmed === 1,
    discoverable: row.discoverable === 1,
    nameSource: row.name_source,
  };
}

function sanitizeDisplayName(value: string): string {
  const clean = value.replace(/\s+/g, ' ').trim();
  if (clean.length < 2 || clean.length > 24) {
    throw new ProfileError(400, 'Display name must be between 2 and 24 characters.');
  }
  const lower = clean.toLowerCase();
  if (UNSAFE_PARTS.some((part) => lower.includes(part))) {
    throw new ProfileError(400, 'This display name is not allowed.');
  }
  return clean;
}

function normalizeUsername(value: string): string {
  return value.trim().toLowerCase();
}

function validateUsername(value: string): void {
  if (!/^[a-z0-9_]{3,20}$/.test(value)) {
    throw new ProfileError(
      400,
      'Username must be 3–20 characters using letters, numbers or underscore.',
    );
  }
  if (RESERVED_USERNAMES.has(value) || UNSAFE_PARTS.some((part) => value.includes(part))) {
    throw new ProfileError(400, 'This username is not allowed.');
  }
}

function normalizeNameSource(value: unknown, fallback: string): string {
  const source = typeof value === 'string' ? value : fallback;
  return ['custom', 'google_play_games', 'game_center'].includes(source)
    ? source
    : 'custom';
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value as Record<string, unknown>;
  } catch {
    throw new ProfileError(400, 'Invalid JSON body.');
  }
}

class ProfileError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

function routeError(env: RuntimeEnv, error: unknown): Response {
  if (error instanceof AppCheckError) {
    return json(env, 403, { error: error.code, code: error.code });
  }
  if (error instanceof ProfileError) {
    return json(env, error.status, { error: error.message });
  }
  console.error('Profile route failed', error);
  return json(env, 500, { error: 'Profile request failed.' });
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
