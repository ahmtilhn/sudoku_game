import app, { GameRoom, MatchmakingQueue } from './profile_wrapper';
import type { Env } from './index';
import { sendPlayerPush } from './push_notifications';

export { GameRoom, MatchmakingQueue };

type RuntimeEnv = Env & {
  ALLOW_TEST_PURCHASE_GRANTS?: string;
};

export default {
  async fetch(
    request: Request,
    env: RuntimeEnv,
    ctx: ExecutionContext,
  ): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(env),
      });
    }

    const url = new URL(request.url);
    if (isUnsafeProductionRewardConfirmation(request, env, url)) {
      return json(env, 503, {
        error:
          'AdMob server-side reward verification is required before production rewards can be granted.',
        code: 'ad_ssv_required',
      });
    }

    const routedRequest = await protectProfileDisplayName(request, url);
    const response = await app.fetch(routedRequest, env, ctx);
    if (response.status === 101) return response;

    if (
      response.status === 201 &&
      request.method === 'POST' &&
      /^\/v1\/matches\/[^/]+\/rematch$/.test(url.pathname)
    ) {
      ctx.waitUntil(notifyRematchRecipient(env, response.clone()));
    }

    const headers = new Headers(response.headers);
    for (const [key, value] of Object.entries(corsHeaders(env))) {
      if (!headers.has(key)) headers.set(key, value);
    }
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  },
};

function isUnsafeProductionRewardConfirmation(
  request: Request,
  env: RuntimeEnv,
  url: URL,
): boolean {
  if ((env.ENVIRONMENT ?? '').toLowerCase() !== 'production') return false;
  if (request.method !== 'POST') return false;
  return (
    url.pathname === '/v1/rewards/daily-ad/confirm' ||
    url.pathname === '/v1/rewards/career-ad/confirm'
  );
}

async function protectProfileDisplayName(
  request: Request,
  url: URL,
): Promise<Request> {
  if (request.method !== 'POST' || url.pathname !== '/v1/me') return request;
  try {
    const body = (await request.clone().json()) as Record<string, unknown>;
    if (!body || typeof body !== 'object' || Array.isArray(body)) return request;
    const sanitized = { ...body };
    delete sanitized.displayName;
    const headers = new Headers(request.headers);
    headers.set('content-type', 'application/json');
    return new Request(request.url, {
      method: request.method,
      headers,
      body: JSON.stringify(sanitized),
    });
  } catch {
    return request;
  }
}

async function notifyRematchRecipient(
  env: RuntimeEnv,
  response: Response,
): Promise<void> {
  try {
    const body = (await response.json()) as Record<string, unknown>;
    const invitationId = String(body.id ?? '');
    const previousMatchId = String(body.previousMatchId ?? '');
    const recipient = asObject(body.recipient);
    const sender = asObject(body.sender);
    const recipientPublicId = String(recipient?.publicId ?? '');
    const senderName = String(sender?.displayName ?? 'A player');
    if (!invitationId || !recipientPublicId) return;

    const player = await env.DB.prepare(
      'SELECT id FROM players WHERE public_id = ? LIMIT 1',
    )
      .bind(recipientPublicId)
      .first<{ id: string }>();
    if (!player) return;

    await sendPlayerPush(env, player.id, {
      title: 'Rematch invitation',
      body: `${senderName} wants to play again. You have 10 seconds to respond.`,
      tag: `rematch_${invitationId}`,
      data: {
        type: 'rematch_invitation',
        rematchId: invitationId,
        previousMatchId,
      },
    });
  } catch (error) {
    console.error('Rematch push failed', error);
  }
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function json(env: RuntimeEnv, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...corsHeaders(env),
    },
  });
}

function corsHeaders(env: RuntimeEnv): Record<string, string> {
  return {
    'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
    'access-control-allow-headers':
      'authorization, content-type, x-firebase-appcheck',
    'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
  };
}
