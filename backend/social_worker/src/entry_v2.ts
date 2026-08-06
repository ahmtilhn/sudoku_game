import legacyWorker, { GameRoom } from './entry';
import {
  MatchmakingQueue,
  handleVariantMatchmakingRequest,
  type VariantMatchmakingEnv,
} from './variant_matchmaking';

export { GameRoom, MatchmakingQueue };

export default {
  async fetch(
    request: Request,
    env: VariantMatchmakingEnv,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/v1/matchmaking/queue') {
      return handleVariantMatchmakingRequest(
        request,
        env,
        ctx,
        (forwarded, forwardedEnv, forwardedCtx) =>
          legacyWorker.fetch(forwarded, forwardedEnv as never, forwardedCtx),
      );
    }
    return legacyWorker.fetch(request, env as never, ctx);
  },

  async scheduled(
    event: ScheduledEvent,
    env: VariantMatchmakingEnv,
    ctx: ExecutionContext,
  ): Promise<void> {
    await legacyWorker.scheduled(event, env as never, ctx);
  },
};
