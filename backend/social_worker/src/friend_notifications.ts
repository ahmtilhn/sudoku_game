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

  if (url.pathname === '/v1/friends/requests') {
    const targetPublicId = stringValue(body.targetPublicId);
    if (targetPublicId != null) {
      ctx.waitUntil(notifyFriendRequest(env, targetPublicId));
    }
  } else if (url.pathname === '/v1/friends/requests/respond') {
    const requesterPublicId = stringValue(body.requesterPublicId);
    const action = stringValue(body.action);
    if (
      requesterPublicId != null &&
      (action === 'accept' || action === 'decline')
    ) {
      ctx.waitUntil(
        notifyFriendResponse(env, requesterPublicId, action === 'accept'),
      );
    }
  }

  return response;
}

async function notifyFriendRequest(
  env: FriendNotificationEnv,
  targetPublicId: string,
): Promise<void> {
  const target = await env.DB.prepare(
    'SELECT id FROM players WHERE public_id = ? LIMIT 1',
  )
    .bind(targetPublicId)
    .first<{ id: string }>();
  if (!target) return;

  const relation = await env.DB.prepare(
    `SELECT f.requester_id, f.status, p.display_name, p.public_id
     FROM friendships f
     JOIN players p ON p.id = f.requester_id
     WHERE (f.player_low_id = ? OR f.player_high_id = ?)
       AND f.status = 'pending'
       AND f.requester_id != ?
     ORDER BY f.updated_at DESC
     LIMIT 1`,
  )
    .bind(target.id, target.id, target.id)
    .first<{
      requester_id: string;
      status: string;
      display_name: string;
      public_id: string;
    }>();
  if (!relation) return;

  await sendPlayerPush(env, target.id, {
    title: 'New friend request',
    body: `${relation.display_name} sent you a friend request.`,
    tag: `friend_request_${relation.requester_id}`,
    data: {
      type: 'friend_request',
      requesterPublicId: relation.public_id,
    },
  });
}

async function notifyFriendResponse(
  env: FriendNotificationEnv,
  requesterPublicId: string,
  accepted: boolean,
): Promise<void> {
  const requester = await env.DB.prepare(
    'SELECT id FROM players WHERE public_id = ? LIMIT 1',
  )
    .bind(requesterPublicId)
    .first<{ id: string }>();
  if (!requester) return;

  const relation = await env.DB.prepare(
    `SELECT f.player_low_id, f.player_high_id, f.status
     FROM friendships f
     WHERE (f.player_low_id = ? OR f.player_high_id = ?)
       AND f.requester_id = ?
     ORDER BY f.updated_at DESC
     LIMIT 1`,
  )
    .bind(requester.id, requester.id, requester.id)
    .first<{
      player_low_id: string;
      player_high_id: string;
      status: string;
    }>();
  if (!relation) return;

  const responderId =
    relation.player_low_id === requester.id
      ? relation.player_high_id
      : relation.player_low_id;
  const responder = await env.DB.prepare(
    'SELECT display_name, public_id FROM players WHERE id = ? LIMIT 1',
  )
    .bind(responderId)
    .first<{ display_name: string; public_id: string }>();
  if (!responder) return;

  await sendPlayerPush(env, requester.id, {
    title: accepted ? 'Friend request accepted' : 'Friend request declined',
    body: accepted
      ? `${responder.display_name} accepted your friend request.`
      : `${responder.display_name} declined your friend request.`,
    tag: `friend_response_${responderId}`,
    data: {
      type: 'friend_response',
      status: accepted ? 'accepted' : 'declined',
      playerPublicId: responder.public_id,
    },
  });
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
