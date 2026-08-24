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

export function isFriendNotificationRoute(pathname: string): boolean {
  return (
    pathname === '/v1/friends/requests' ||
    pathname === '/v1/friends/requests/respond'
  );
}

export async function handleFriendNotificationRequest(
  request: Request,
  env: FriendNotificationEnv,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
): Promise<Response> {
  const url = new URL(request.url);
  const body = await readJsonClone(request);
  const response = await legacyFetch(request, env, ctx);
  if (!response.ok || request.method !== 'POST') return response;

  // The legacy request already authenticated this exact bearer token. Decode
  // only after success to identify the actor for the best-effort notification;
  // authorization continues to be owned by the legacy handler.
  const actor = await authenticatedPlayer(env, request);
  if (actor == null) return response;

  if (url.pathname === '/v1/friends/requests') {
    const targetPublicId = stringValue(body.targetPublicId);
    if (targetPublicId != null) {
      ctx.waitUntil(notifyFriendRequest(env, actor, targetPublicId));
    }
  } else if (url.pathname === '/v1/friends/requests/respond') {
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
  }

  return response;
}

async function notifyFriendRequest(
  env: FriendNotificationEnv,
  requester: PlayerIdentity,
  targetPublicId: string,
): Promise<void> {
  const target = await env.DB.prepare(
    'SELECT id FROM players WHERE public_id = ? LIMIT 1',
  )
    .bind(targetPublicId)
    .first<{ id: string }>();
  if (!target || target.id === requester.id) return;

  const [low, high] = [requester.id, target.id].sort();
  const relation = await env.DB.prepare(
    `SELECT requester_id, status FROM friendships
     WHERE player_low_id = ? AND player_high_id = ? LIMIT 1`,
  )
    .bind(low, high)
    .first<{ requester_id: string; status: string }>();

  // Do not notify for an already-accepted relationship or for a reverse
  // pending request. This also makes repeated send taps notification-idempotent.
  if (
    relation?.status !== 'pending' ||
    relation.requester_id !== requester.id
  ) {
    return;
  }

  await sendPlayerPush(env, target.id, {
    title: 'New friend request',
    body: `${requester.display_name} sent you a friend request.`,
    tag: `friend_request_${requester.id}`,
    data: {
      type: 'friend_request',
      requesterPublicId: requester.public_id,
    },
  });
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
    title: accepted ? 'Friend request accepted' : 'Friend request declined',
    body: accepted
      ? `${responder.display_name} accepted your friend request.`
      : `${responder.display_name} declined your friend request.`,
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
