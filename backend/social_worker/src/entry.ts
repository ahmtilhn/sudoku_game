import app, { GameRoom, MatchmakingQueue } from './profile_wrapper';
import type { Env } from './index';

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

    const response = await app.fetch(request, env, ctx);
    if (response.status === 101) return response;

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

function corsHeaders(env: RuntimeEnv): Record<string, string> {
  return {
    'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
    'access-control-allow-headers':
      'authorization, content-type, x-firebase-appcheck',
    'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
  };
}
