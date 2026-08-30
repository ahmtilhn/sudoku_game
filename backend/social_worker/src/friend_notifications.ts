import { sendPlayerPush, type PushEnv } from './push_notifications';

type JsonObject = Record<string, unknown>;

type FriendNotificationEnv = PushEnv & {
  ALLOWED_ORIGIN?: string;
};

type LegacyFetch = (
  request: Request,
  env: FriendNotificationEnv,
  ctx: ExecutionContext,
) => Promise<Response>;

type PlayerIdentity = {
  id: string;
  display_name: string;
  public_id: string;
};

type Relation = {
  requester_id: string;
  status: string;
};

type PlayerRow = Record<string, unknown> & {
  id: string;
  public_id: string;
  username: string;
  display_name: string;
  avatar_key: string;
  rating: number;
  games_played: number;
  wins: number;
  losses: number;
  achievement_count: number;
  friendship_status?: string | null;
  last_played_at?: string | null;
};

export type FriendshipPresentationStatus =
  | 'accepted'
  | 'outgoing_pending'
  | 'incoming_pending'
  | null;

export type FriendRequestConflict = {
  status: number;
  code: string;
  message: string;
  friendshipStatus: FriendshipPresentationStatus;
};

export function friendshipPresentationStatus(
  relation: Relation | null,
  viewerId: string,
): FriendshipPresentationStatus {
  if (relation == null) return null;
  if (relation.status === 'accepted') return 'accepted';
  if (relation.status !== 'pending') return null;
  return relation.requester_id === viewerId
    ? 'outgoing_pending'
    : 'incoming_pending';
}

export function friendRequestConflict(
  relation: Relation | null,
  requesterId: string,
  targetId: string,
): FriendRequestConflict | null {
  if (relation == null || relation.status === 'declined') return null;
  if (relation.status === 'blocked') {
    return {
      status: 403,
      code: 'player_unavailable',
      message: 'This player is unavailable.',
      friendshipStatus: null,
    };
  }
  if (relation.status === 'accepted') {
    return {
      status: 409,
      code: 'already_friends',
      message: 'Already friends.',
      friendshipStatus: 'accepted',
    };
  }
  if (relation.status === 'pending') {
    if (relation.requester_id === requesterId) {
      return {
        status: 409,
        code: 'friend_request_already_pending',
        message: 'Friend request is already pending.',
        friendshipStatus: 'outgoing_pending',
      };
    }
    if (relation.requester_id === targetId) {
      return {
        status: 409,
        code: 'incoming_friend_request_pending',
        message: 'Incoming friend request is already pending.',
        friendshipStatus: 'incoming_pending',
      };
    }
  }
  return {
    status: 409,
    code: 'friendship_conflict',
    message: 'Friendship state changed. Refresh and try again.',
    friendshipStatus: null,
  };
}

export function isFriendNotificationRoute(pathname: string): boolean {
  return (
    pathname === '/v1/friends/requests' ||
    pathname === '/v1/friends/requests/respond' ||
    pathname === '/v1/players/search' ||
    pathname === '/v1/opponents/recent'
  );
}

export async function handleFriendNotificationRequest(
  request: Request,
  env: FriendNotificationEnv,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === 'GET') {
    if (url.pathname === '/v1/players/search') {
      return handleSearch(request, env, ctx, legacyFetch, url);
    }
    if (url.pathname === '/v1/opponents/recent') {
      return handleRecentOpponents(request, env, ctx, legacyFetch);
    }
    return legacyFetch(request, env, ctx);
  }

  if (request.method !== 'POST') {
    return legacyFetch(request, env, ctx);
  }

  const body = await readJsonClone(request);
  if (url.pathname === '/v1/friends/requests') {
    return createFriendRequest(request, env, ctx, legacyFetch, body);
  }

  const response = await legacyFetch(request, env, ctx);
  if (!response.ok || url.pathname !== '/v1/friends/requests/respond') {
    return response;
  }

  // The legacy response endpoint authenticated and authorized the exact bearer
  // token and verified that this actor was the pending request recipient.
  const actor = await authenticatedPlayer(env, request);
  if (actor == null) return response;
  const requesterPublicId = stringValue(body.requesterPublicId);
  const action = stringValue(body.action);
  if (
    requesterPublicId != null &&
    (action === 'accept' || action === 'decline')
  ) {
    ctx.waitUntil(
      notifyFriendResponse(
        env,
        actor,
        requesterPublicId,
        action === 'accept',
      ),
    );
  }
  return response;
}

async function createFriendRequest(
  request: Request,
  env: FriendNotificationEnv,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
  body: JsonObject,
): Promise<Response> {
  // Authenticate through the existing worker without allowing its legacy
  // friend-request mutation to run. After this succeeds, decoding the same
  // bearer token is only used to identify the already-authenticated actor.
  const authRequest = new Request(new URL('/v1/friends', request.url), {
    method: 'GET',
    headers: request.headers,
  });
  const authResponse = await legacyFetch(authRequest, env, ctx);
  if (!authResponse.ok) return authResponse;

  const actor = await authenticatedPlayer(env, request);
  if (actor == null) {
    return jsonLike(authResponse, 401, {
      error: 'Invalid or expired Firebase ID token.',
      code: 'invalid_authentication',
    });
  }

  const rateLimitAllowed = await consumeRateLimit(
    env,
    `friend:${actor.id}`,
    20,
    3600,
  );
  if (!rateLimitAllowed) {
    return jsonLike(authResponse, 429, {
      error: 'Too many requests. Try again later.',
      code: 'friend_request_rate_limited',
    });
  }

  const targetPublicId = requiredPublicId(body.targetPublicId);
  if (targetPublicId == null) {
    return jsonLike(authResponse, 400, {
      error: 'targetPublicId is invalid.',
      code: 'invalid_target_public_id',
    });
  }

  const target = await env.DB.prepare(
    `SELECT id, display_name, public_id
     FROM players WHERE public_id = ? LIMIT 1`,
  )
    .bind(targetPublicId)
    .first<PlayerIdentity>();
  if (target == null) {
    return jsonLike(authResponse, 404, {
      error: 'Player not found.',
      code: 'player_not_found',
    });
  }
  if (target.id === actor.id) {
    return jsonLike(authResponse, 400, {
      error: 'You cannot add yourself.',
      code: 'cannot_add_self',
    });
  }

  const [low, high] = orderedPair(actor.id, target.id);
  const now = new Date().toISOString();

  // This conditional UPSERT is the state-machine boundary. It creates a new
  // request or re-opens a declined relationship, but it NEVER rewrites the
  // requester of pending/accepted/blocked rows. Concurrent crossed requests
  // therefore cannot flip requester_id based on last-writer-wins ordering.
  const mutation = await env.DB.prepare(
    `INSERT INTO friendships (
       player_low_id, player_high_id, requester_id, status, created_at, updated_at
     ) VALUES (?, ?, ?, 'pending', ?, ?)
     ON CONFLICT(player_low_id, player_high_id) DO UPDATE SET
       requester_id = excluded.requester_id,
       status = 'pending',
       updated_at = excluded.updated_at
     WHERE friendships.status = 'declined'`,
  )
    .bind(low, high, actor.id, now, now)
    .run();

  const changed = Number(mutation.meta?.changes ?? 0) > 0;
  if (!changed) {
    const relation = await env.DB.prepare(
      `SELECT requester_id, status FROM friendships
       WHERE player_low_id = ? AND player_high_id = ? LIMIT 1`,
    )
      .bind(low, high)
      .first<Relation>();
    const conflict = friendRequestConflict(relation, actor.id, target.id);
    if (conflict != null) {
      return jsonLike(authResponse, conflict.status, {
        error: conflict.message,
        code: conflict.code,
        friendshipStatus: conflict.friendshipStatus,
      });
    }
    return jsonLike(authResponse, 409, {
      error: 'Friendship state changed. Refresh and try again.',
      code: 'friendship_conflict',
    });
  }

  ctx.waitUntil(
    sendPlayerPush(env, target.id, {
      titleKey: 'push_friend_request_title',
      bodyKey: 'push_friend_request_body',
      tag: `friend_request_${actor.id}`,
      data: {
        type: 'friend_request',
        requesterPublicId: actor.public_id,
      },
    }),
  );

  return jsonLike(authResponse, 201, {
    ok: true,
    friendshipStatus: 'outgoing_pending',
  });
}

async function handleSearch(
  request: Request,
  env: FriendNotificationEnv,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
  url: URL,
): Promise<Response> {
  // Preserve the existing App Check/authentication/profile creation and search
  // rate-limit behavior, then replace only the result query with the hardened
  // directional relationship projection.
  const authorized = await legacyFetch(request, env, ctx);
  if (!authorized.ok) return authorized;
  const actor = await authenticatedPlayer(env, request);
  if (actor == null) return authorized;

  const raw = (url.searchParams.get('q') ?? '').trim();
  if (raw.length < 3 || raw.length > 64) {
    return jsonLike(authorized, 200, { players: [] });
  }
  const normalized = raw.toLowerCase();
  const usernamePattern = `%${normalized}%`;
  const displayPattern = `%${raw.toLowerCase()}%`;

  const rows = await env.DB.prepare(
    `SELECT p.*,
       CASE
         WHEN f.status IS NULL THEN NULL
         WHEN f.status = 'accepted' THEN 'accepted'
         WHEN f.status = 'pending' AND f.requester_id = ? THEN 'outgoing_pending'
         WHEN f.status = 'pending' THEN 'incoming_pending'
         ELSE NULL
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
       AND NOT EXISTS (
         SELECT 1 FROM friendships b
         WHERE b.player_low_id = CASE WHEN p.id < ? THEN p.id ELSE ? END
           AND b.player_high_id = CASE WHEN p.id < ? THEN ? ELSE p.id END
           AND b.status = 'blocked'
       )
     ORDER BY
       CASE WHEN p.public_id = upper(?) THEN 0 ELSE 1 END,
       p.rating DESC,
       p.username_normalized
     LIMIT 40`,
  )
    .bind(
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      raw,
      usernamePattern,
      displayPattern,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      raw,
    )
    .all<PlayerRow>();

  return jsonLike(authorized, 200, {
    players: rows.results.map(playerJson),
  });
}

async function handleRecentOpponents(
  request: Request,
  env: FriendNotificationEnv,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
): Promise<Response> {
  const authorized = await legacyFetch(request, env, ctx);
  if (!authorized.ok) return authorized;
  const actor = await authenticatedPlayer(env, request);
  if (actor == null) return authorized;

  const rows = await env.DB.prepare(
    `SELECT p.*, r.last_played_at,
       CASE
         WHEN f.status IS NULL THEN NULL
         WHEN f.status = 'accepted' THEN 'accepted'
         WHEN f.status = 'pending' AND f.requester_id = ? THEN 'outgoing_pending'
         WHEN f.status = 'pending' THEN 'incoming_pending'
         ELSE NULL
       END AS friendship_status
     FROM recent_opponents r
     JOIN players p ON p.id = CASE
       WHEN r.player_low_id = ? THEN r.player_high_id
       ELSE r.player_low_id END
     LEFT JOIN friendships f
       ON f.player_low_id = CASE WHEN p.id < ? THEN p.id ELSE ? END
      AND f.player_high_id = CASE WHEN p.id < ? THEN ? ELSE p.id END
     WHERE (r.player_low_id = ? OR r.player_high_id = ?)
       AND NOT EXISTS (
         SELECT 1 FROM friendships b
         WHERE b.player_low_id = CASE WHEN p.id < ? THEN p.id ELSE ? END
           AND b.player_high_id = CASE WHEN p.id < ? THEN ? ELSE p.id END
           AND b.status = 'blocked'
       )
     ORDER BY r.last_played_at DESC
     LIMIT 50`,
  )
    .bind(
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
      actor.id,
    )
    .all<PlayerRow>();

  return jsonLike(authorized, 200, {
    players: rows.results.map(playerJson),
  });
}

function playerJson(player: PlayerRow): JsonObject {
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

async function notifyFriendResponse(
  env: FriendNotificationEnv,
  responder: PlayerIdentity,
  requesterPublicId: string,
  accepted: boolean,
): Promise<void> {
  const requester = await env.DB.prepare(
    'SELECT id FROM players WHERE public_id = ? LIMIT 1',
  )
    .bind(requesterPublicId)
    .first<{ id: string }>();
  if (!requester || requester.id === responder.id) return;

  await sendPlayerPush(env, requester.id, {
    titleKey: accepted
      ? 'push_friend_accepted_title'
      : 'push_friend_declined_title',
    bodyKey: accepted
      ? 'push_friend_accepted_body'
      : 'push_friend_declined_body',
    tag: `friend_response_${responder.id}`,
    data: {
      type: 'friend_response',
      status: accepted ? 'accepted' : 'declined',
      playerPublicId: responder.public_id,
    },
  });
}

async function authenticatedPlayer(
  env: FriendNotificationEnv,
  request: Request,
): Promise<PlayerIdentity | null> {
  const header = request.headers.get('authorization')?.trim() ?? '';
  if (!header.toLowerCase().startsWith('bearer ')) return null;
  const token = header.slice(7).trim();
  const parts = token.split('.');
  if (parts.length < 2) return null;

  try {
    const payload = JSON.parse(base64UrlDecode(parts[1])) as JsonObject;
    const firebaseUid = stringValue(payload.sub) ?? stringValue(payload.user_id);
    if (firebaseUid == null) return null;
    return env.DB.prepare(
      `SELECT id, display_name, public_id
       FROM players WHERE firebase_uid = ? LIMIT 1`,
    )
      .bind(firebaseUid)
      .first<PlayerIdentity>();
  } catch (_) {
    return null;
  }
}

async function consumeRateLimit(
  env: FriendNotificationEnv,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
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
       ON CONFLICT(key) DO UPDATE SET
         window_started_at = excluded.window_started_at,
         count = 1`,
    )
      .bind(key, now)
      .run();
    return true;
  }

  if (current.count >= limit) return false;
  await env.DB.prepare(
    'UPDATE request_limits SET count = count + 1 WHERE key = ?',
  )
    .bind(key)
    .run();
  return true;
}

function requiredPublicId(value: unknown): string | null {
  const text = stringValue(value)?.toUpperCase() ?? '';
  return text.length >= 4 && text.length <= 64 ? text : null;
}

function orderedPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a];
}

function jsonLike(
  source: Response,
  status: number,
  body: JsonObject,
): Response {
  const headers = new Headers(source.headers);
  headers.set('content-type', 'application/json; charset=utf-8');
  return new Response(JSON.stringify(body), { status, headers });
}

function base64UrlDecode(value: string): string {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '=',
  );
  return atob(padded);
}

async function readJsonClone(request: Request): Promise<JsonObject> {
  try {
    const value = await request.clone().json();
    return value != null && typeof value === 'object' && !Array.isArray(value)
      ? (value as JsonObject)
      : {};
  } catch (_) {
    return {};
  }
}

function stringValue(value: unknown): string | null {
  const text = typeof value === 'string' ? value.trim() : '';
  return text.length > 0 ? text : null;
}
