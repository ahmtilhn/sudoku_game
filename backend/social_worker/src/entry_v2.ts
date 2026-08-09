import legacyWorker, { GameRoom } from './entry';
import {
  MatchmakingQueue,
  handleVariantMatchmakingRequest,
  type VariantMatchmakingEnv,
} from './variant_matchmaking';
import {
  handleVariantChallengeRequest,
  isVariantChallengeRoute,
} from './variant_challenges';
import {
  handleEconomyV3Request,
  isEconomyV3Route,
  isLegacyEconomyRewardRoute,
  legacyEconomyRewardResponse,
} from './economy_v3';
import type { EconomyV3Env } from './economy_v3_common';

export { GameRoom, MatchmakingQueue };

export default {
  async fetch(
    request: Request,
    env: VariantMatchmakingEnv,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== 'OPTIONS' && isLegacyEconomyRewardRoute(url.pathname)) {
      return legacyEconomyRewardResponse(env as unknown as EconomyV3Env);
    }
    if (request.method !== 'OPTIONS' && isEconomyV3Route(url.pathname)) {
      return handleEconomyV3Request(
        request,
        env as unknown as EconomyV3Env,
        ctx,
        (forwarded) => legacyWorker.fetch(forwarded, env as never, ctx),
      );
    }
    if (
      url.pathname === '/v1/matchmaking/queue' &&
      request.method !== 'OPTIONS'
    ) {
      return handleVariantMatchmakingRequest(
        request,
        env,
        ctx,
        (forwarded, forwardedEnv, forwardedCtx) =>
          legacyWorker.fetch(forwarded, forwardedEnv as never, forwardedCtx),
      );
    }
    if (isVariantChallengeRoute(url.pathname) && request.method !== 'OPTIONS') {
      return handleVariantChallengeRequest(
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
