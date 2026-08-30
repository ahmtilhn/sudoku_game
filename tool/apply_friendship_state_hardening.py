from __future__ import annotations

from pathlib import Path
import textwrap


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one replacement target, found {count}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


FRIEND_NOTIFICATIONS = r"""import { sendPlayerPush, type PushEnv } from './push_notifications';

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

  await enforceRateLimit(env, `friend:${actor.id}`, 20, 3600);

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

async function enforceRateLimit(
  env: FriendNotificationEnv,
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
       ON CONFLICT(key) DO UPDATE SET
         window_started_at = excluded.window_started_at,
         count = 1`,
    )
      .bind(key, now)
      .run();
    return;
  }

  if (current.count >= limit) {
    throw new Error('friend_request_rate_limited');
  }
  await env.DB.prepare(
    'UPDATE request_limits SET count = count + 1 WHERE key = ?',
  )
    .bind(key)
    .run();
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
"""

# Replace the complete production/staging friend wrapper with an atomic state-machine.
Path("backend/social_worker/src/friend_notifications.ts").write_text(
    FRIEND_NOTIFICATIONS,
    encoding="utf-8",
)

# Route GET search/recent-opponent traffic through the same friendship hardening wrapper.
replace_once(
    "backend/social_worker/src/entry_v2.ts",
    """    if (\n      request.method === 'POST' &&\n      isFriendNotificationRoute(url.pathname)\n    ) {\n""",
    """    if (\n      request.method !== 'OPTIONS' &&\n      isFriendNotificationRoute(url.pathname)\n    ) {\n""",
)

# Active Friends hub: incoming requests are actionable, never addable, and search state refreshes after mutations.
replace_once(
    "lib/features/social/social_hub_screen.dart",
    """    try {\n      await action();\n      await _load();\n    } catch (error) {\n""",
    """    try {\n      await action();\n      await _load();\n      if (_search.text.trim().length >= 3) {\n        await _findPlayers();\n      }\n    } catch (error) {\n""",
)

replace_once(
    "lib/features/social/social_hub_screen.dart",
    """  bool _canAdd(SocialPlayer p) =>\n      p.friendshipStatus != 'accepted' &&\n      p.friendshipStatus != 'pending' &&\n      p.friendshipStatus != 'outgoing_pending';\n\n  String _friendLabel(SocialPlayer p) {\n    if (p.friendshipStatus == 'accepted') return context.tr('friends');\n    if (!_canAdd(p)) return context.tr('friend_request_sent');\n    return context.tr('add_friend');\n  }\n""",
    """  bool _isIncomingRequest(SocialPlayer p) =>\n      p.friendshipStatus == 'incoming_pending';\n\n  bool _canAdd(SocialPlayer p) =>\n      p.friendshipStatus != 'accepted' &&\n      p.friendshipStatus != 'pending' &&\n      p.friendshipStatus != 'outgoing_pending' &&\n      p.friendshipStatus != 'incoming_pending';\n\n  String _friendBusyId(SocialPlayer p) => _isIncomingRequest(p)\n      ? 'request-${p.publicId}'\n      : 'friend-${p.publicId}';\n\n  String _friendLabel(SocialPlayer p) {\n    if (p.friendshipStatus == 'accepted') return context.tr('friends');\n    if (_isIncomingRequest(p)) return context.tr('accept');\n    if (!_canAdd(p)) return context.tr('friend_request_sent');\n    return context.tr('add_friend');\n  }\n""",
)

replace_once(
    "lib/features/social/social_hub_screen.dart",
    """                                  _SearchPlayer(\n                                    player: p,\n                                    rank: _rankFor(p.publicId),\n                                    busy: _busyId == 'friend-${p.publicId}',\n                                    enabled: _canAdd(p),\n                                    label: _friendLabel(p),\n                                    onTap: () => _showPlayer(\n                                      p,\n                                      primaryLabel: _friendLabel(p),\n                                      onPrimary: _canAdd(p)\n                                          ? () => _sendFriendRequest(p)\n                                          : null,\n                                    ),\n                                    onAction: () => _sendFriendRequest(p),\n                                  ),\n""",
    """                                  _SearchPlayer(\n                                    player: p,\n                                    rank: _rankFor(p.publicId),\n                                    busy: _busyId == _friendBusyId(p),\n                                    enabled:\n                                        _isIncomingRequest(p) || _canAdd(p),\n                                    label: _friendLabel(p),\n                                    onTap: () => _showPlayer(\n                                      p,\n                                      primaryLabel: _friendLabel(p),\n                                      onPrimary: _isIncomingRequest(p)\n                                          ? () => _respondRequest(p, true)\n                                          : _canAdd(p)\n                                          ? () => _sendFriendRequest(p)\n                                          : null,\n                                      secondaryLabel: _isIncomingRequest(p)\n                                          ? context.tr('decline')\n                                          : null,\n                                      onSecondary: _isIncomingRequest(p)\n                                          ? () => _respondRequest(p, false)\n                                          : null,\n                                    ),\n                                    onAction: _isIncomingRequest(p)\n                                        ? () => _respondRequest(p, true)\n                                        : () => _sendFriendRequest(p),\n                                  ),\n""",
)

replace_once(
    "lib/features/social/social_hub_screen.dart",
    """        _PlayerCard(\n          player: p,\n          rank: _rankFor(p.publicId),\n          busy: _busyId == 'friend-${p.publicId}',\n          enabled: _canAdd(p),\n          primary: _friendLabel(p),\n          meta: _lastPlayed(p.lastPlayedAt),\n          onTap: () => _showPlayer(\n            p,\n            primaryLabel: _friendLabel(p),\n            onPrimary: _canAdd(p) ? () => _sendFriendRequest(p) : null,\n          ),\n          onPrimary: () => _sendFriendRequest(p),\n        ),\n""",
    """        _PlayerCard(\n          player: p,\n          rank: _rankFor(p.publicId),\n          busy: _busyId == _friendBusyId(p),\n          enabled: _isIncomingRequest(p) || _canAdd(p),\n          primary: _friendLabel(p),\n          secondary: _isIncomingRequest(p) ? context.tr('decline') : null,\n          meta: _lastPlayed(p.lastPlayedAt),\n          onTap: () => _showPlayer(\n            p,\n            primaryLabel: _friendLabel(p),\n            onPrimary: _isIncomingRequest(p)\n                ? () => _respondRequest(p, true)\n                : _canAdd(p)\n                ? () => _sendFriendRequest(p)\n                : null,\n            secondaryLabel: _isIncomingRequest(p)\n                ? context.tr('decline')\n                : null,\n            onSecondary: _isIncomingRequest(p)\n                ? () => _respondRequest(p, false)\n                : null,\n          ),\n          onPrimary: _isIncomingRequest(p)\n              ? () => _respondRequest(p, true)\n              : () => _sendFriendRequest(p),\n          onSecondary: _isIncomingRequest(p)\n              ? () => _respondRequest(p, false)\n              : null,\n        ),\n""",
)

# Legacy/platform social screen: protect every send entry from duplicate and pending-state taps.
replace_once(
    "lib/features/social/platform_social_screen.dart",
    """  List<SocialPlayer> _searchResults = const <SocialPlayer>[];\n  List<SocialChallenge> _pendingChallenges = const <SocialChallenge>[];\n\n  bool get _backendReady => _push.configured && _social.configured;\n""",
    """  List<SocialPlayer> _searchResults = const <SocialPlayer>[];\n  List<SocialChallenge> _pendingChallenges = const <SocialChallenge>[];\n  final Set<String> _friendRequestsInFlight = <String>{};\n\n  bool get _backendReady => _push.configured && _social.configured;\n""",
)

replace_once(
    "lib/features/social/platform_social_screen.dart",
    """  Future<void> _addFriend(SocialPlayer player) async {\n    try {\n      await _social.sendFriendRequest(player.publicId);\n      if (!mounted) return;\n      _showMessage(\n        context.tr('friend_request_sent_to', <Object>[player.displayName]),\n      );\n      await _refreshSocial(showLoading: false);\n    } on SocialApiException catch (error) {\n      if (!mounted) return;\n      _showMessage(UserSafeError.message(context, error));\n    }\n  }\n""",
    """  Future<void> _addFriend(SocialPlayer player) async {\n    final id = player.publicId;\n    if (_friendRequestsInFlight.contains(id)) return;\n    setState(() => _friendRequestsInFlight.add(id));\n    try {\n      await _social.sendFriendRequest(id);\n      if (!mounted) return;\n      _showMessage(\n        context.tr('friend_request_sent_to', <Object>[player.displayName]),\n      );\n      await _refreshSocial(showLoading: false);\n    } on SocialApiException catch (error) {\n      if (!mounted) return;\n      _showMessage(UserSafeError.message(context, error));\n    } finally {\n      if (mounted) {\n        setState(() => _friendRequestsInFlight.remove(id));\n      }\n    }\n  }\n""",
)

replace_once(
    "lib/features/social/platform_social_screen.dart",
    """                        if (onAddFriend != null &&\n                            player.friendshipStatus != 'accepted')\n                          IconButton.outlined(\n""",
    """                        if (onAddFriend != null &&\n                            player.friendshipStatus != 'accepted' &&\n                            player.friendshipStatus != 'pending' &&\n                            player.friendshipStatus != 'outgoing_pending' &&\n                            player.friendshipStatus != 'incoming_pending')\n                          IconButton.outlined(\n""",
)

# Post-game result: do not expose Add Friend before authoritative relationship load completes.
replace_once(
    "lib/features/duel/online_duel_screen.dart",
    """  bool _busy = false;\n  bool _openingAcceptedRoom = false;\n  String? _statusMessage;\n  String? _friendshipStatus;\n""",
    """  bool _busy = false;\n  bool _openingAcceptedRoom = false;\n  bool _friendshipStatusLoading = true;\n  String? _statusMessage;\n  String? _friendshipStatus;\n""",
)

replace_once(
    "lib/features/duel/online_duel_screen.dart",
    """      setState(() {\n        _friendshipStatus = 'pending';\n        _statusMessage = context.tr('friend_request_sent');\n      });\n""",
    """      setState(() {\n        _friendshipStatus = 'outgoing_pending';\n        _statusMessage = context.tr('friend_request_sent');\n      });\n""",
)

replace_once(
    "lib/features/duel/online_duel_screen.dart",
    """        if (message.contains('already friends')) {\n          _friendshipStatus = 'accepted';\n        } else if (message.contains('pending')) {\n          _friendshipStatus = 'pending';\n        }\n""",
    """        if (message.contains('already friends')) {\n          _friendshipStatus = 'accepted';\n        } else if (message.contains('incoming')) {\n          _friendshipStatus = 'incoming_pending';\n        } else if (message.contains('pending')) {\n          _friendshipStatus = 'outgoing_pending';\n        }\n""",
)

replace_once(
    "lib/features/duel/online_duel_screen.dart",
    """  bool get _canAddFriend =>\n      _friendshipStatus != 'accepted' && _friendshipStatus != 'pending';\n\n  Future<void> _loadFriendshipStatus() async {\n""",
    """  bool get _canAddFriend =>\n      !_friendshipStatusLoading &&\n      _friendshipStatus != 'accepted' &&\n      _friendshipStatus != 'pending' &&\n      _friendshipStatus != 'outgoing_pending' &&\n      _friendshipStatus != 'incoming_pending';\n\n  Future<void> _loadFriendshipStatus() async {\n""",
)

replace_once(
    "lib/features/duel/online_duel_screen.dart",
    """    } catch (error) {\n      debugPrint('Result friendship status unavailable: $error');\n    }\n  }\n}\n""",
    """    } catch (error) {\n      debugPrint('Result friendship status unavailable: $error');\n    } finally {\n      if (mounted) setState(() => _friendshipStatusLoading = false);\n    }\n  }\n}\n""",
)

# Source-level regression coverage for all UI entry points and routing contracts.
Path("test/friendship_state_hardening_test.dart").write_text(
    textwrap.dedent(
        r'''\
        import 'dart:io';

        import 'package:flutter_test/flutter_test.dart';

        void main() {
          test('friends hub treats incoming pending as accept-or-decline', () {
            final source = File(
              'lib/features/social/social_hub_screen.dart',
            ).readAsStringSync();

            expect(source, contains("p.friendshipStatus != 'incoming_pending'"));
            expect(source, contains("p.friendshipStatus == 'incoming_pending'"));
            expect(source, contains("? () => _respondRequest(p, true)"));
            expect(source, contains("? () => _respondRequest(p, false)"));
            expect(source, contains('await _findPlayers();'));
          });

          test('legacy platform screen cannot resend pending relationships', () {
            final source = File(
              'lib/features/social/platform_social_screen.dart',
            ).readAsStringSync();

            expect(source, contains("player.friendshipStatus != 'pending'"));
            expect(source, contains("player.friendshipStatus != 'outgoing_pending'"));
            expect(source, contains("player.friendshipStatus != 'incoming_pending'"));
            expect(source, contains('_friendRequestsInFlight.contains(id)'));
          });

          test('post-game add friend waits for relationship lookup', () {
            final source = File(
              'lib/features/duel/online_duel_screen.dart',
            ).readAsStringSync();

            expect(source, contains('bool _friendshipStatusLoading = true;'));
            expect(source, contains('!_friendshipStatusLoading &&'));
            expect(source, contains("_friendshipStatus != 'outgoing_pending'"));
            expect(source, contains("_friendshipStatus != 'incoming_pending'"));
            expect(source, contains('_friendshipStatusLoading = false'));
          });

          test('production entry routes friendship reads and writes through hardening', () {
            final source = File(
              'backend/social_worker/src/entry_v2.ts',
            ).readAsStringSync();
            final friendSource = File(
              'backend/social_worker/src/friend_notifications.ts',
            ).readAsStringSync();

            expect(source, contains("request.method !== 'OPTIONS'"));
            expect(friendSource, contains("pathname === '/v1/players/search'"));
            expect(friendSource, contains("pathname === '/v1/opponents/recent'"));
            expect(friendSource, contains("WHERE friendships.status = 'declined'"));
            expect(friendSource, contains("code: 'already_friends'"));
            expect(friendSource, contains("code: 'friend_request_already_pending'"));
            expect(friendSource, contains("code: 'incoming_friend_request_pending'"));
            expect(friendSource, contains("AND b.status = 'blocked'"));
          });
        }
        '''
    ),
    encoding="utf-8",
)

Path("backend/social_worker/test/friendship_hardening.test.ts").write_text(
    textwrap.dedent(
        r'''\
        import { describe, expect, it } from 'vitest';

        import {
          friendRequestConflict,
          friendshipPresentationStatus,
        } from '../src/friend_notifications';

        describe('friendship state hardening', () => {
          it('keeps pending direction explicit', () => {
            const outgoing = { requester_id: 'a', status: 'pending' };
            const incoming = { requester_id: 'b', status: 'pending' };

            expect(friendshipPresentationStatus(outgoing, 'a')).toBe(
              'outgoing_pending',
            );
            expect(friendshipPresentationStatus(incoming, 'a')).toBe(
              'incoming_pending',
            );
          });

          it('rejects duplicate outgoing requests without changing direction', () => {
            expect(
              friendRequestConflict(
                { requester_id: 'a', status: 'pending' },
                'a',
                'b',
              ),
            ).toMatchObject({
              status: 409,
              code: 'friend_request_already_pending',
              friendshipStatus: 'outgoing_pending',
            });
          });

          it('rejects reverse pending requests without changing requester', () => {
            expect(
              friendRequestConflict(
                { requester_id: 'b', status: 'pending' },
                'a',
                'b',
              ),
            ).toMatchObject({
              status: 409,
              code: 'incoming_friend_request_pending',
              friendshipStatus: 'incoming_pending',
            });
          });

          it('rejects accepted and blocked relationships', () => {
            expect(
              friendRequestConflict(
                { requester_id: 'a', status: 'accepted' },
                'a',
                'b',
              ),
            ).toMatchObject({ status: 409, code: 'already_friends' });
            expect(
              friendRequestConflict(
                { requester_id: 'a', status: 'blocked' },
                'a',
                'b',
              ),
            ).toMatchObject({ status: 403, code: 'player_unavailable' });
          });

          it('allows a declined relationship to be requested again', () => {
            expect(
              friendRequestConflict(
                { requester_id: 'b', status: 'declined' },
                'a',
                'b',
              ),
            ).toBeNull();
          });
        });
        '''
    ),
    encoding="utf-8",
)

print("Friendship state hardening patch applied successfully.")
