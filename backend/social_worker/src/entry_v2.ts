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
import {
  handleFriendNotificationRequest,
  isFriendNotificationRoute,
} from './friend_notifications';
import {
  handleRankProgressionRequest,
  isRankProgressionRoute,
  type RankProgressionEnv,
} from './rank_progression';
import {
  handleRankMatchResultRequest,
  isRankMatchResultRoute,
} from './rank_match_result';
import {
  handlePublicRankProfileRequest,
  isPublicRankProfileRoute,
} from './rank_public_profile';
import {
  handleRankCountryFlagRequest,
  isRankCountryFlagRoute,
  type RankCountryFlagEnv,
} from './rank_country_flags';
import { ensureRankProgressionSchema } from './rank_progression_schema';
import { ensureCompetitiveEconomyHardening } from './competitive_economy_hardening';
import { ensureRuntimeSchema } from './runtime_schema';

export { GameRoom, MatchmakingQueue };

const SUPPORTED_LEADERBOARD_SCOPES = new Set([
  'global',
  'friends',
  'beginner',
  'easy',
  'medium',
  'hard',
  'expert',
]);

export default {
  async fetch(
    request: Request,
    env: VariantMatchmakingEnv,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== 'OPTIONS') {
      try {
        // Install the complete legacy trigger set first, then replace only the
        // competitive/economy-sensitive definitions with hardened versions.
        // This keeps fresh/staging databases complete while preventing the old
        // runtime installer from restoring weaker definitions afterward.
        await ensureRuntimeSchema(env);
        await ensureCompetitiveEconomyHardening(env);
      } catch (error) {
        console.error('competitive_economy_hardening_install_failed', error);
        return leaderboardError(
          env,
          503,
          'The competitive economy is temporarily unavailable.',
          'competitive_economy_schema_unavailable',
        );
      }
    }

    // Visible RP/profile identity is an additive wrapper route. The existing
    // matchmaking, Durable Object room protocol, Elo/MMR settlement and Coin
    // escrow paths below remain unchanged.
    if (
      request.method !== 'OPTIONS' &&
      (isRankProgressionRoute(url.pathname) ||
        isRankMatchResultRoute(url.pathname) ||
        isPublicRankProfileRoute(url.pathname) ||
        isRankCountryFlagRoute(url.pathname))
    ) {
      try {
        await ensureRankProgressionSchema(
          env as unknown as RankProgressionEnv,
        );
      } catch (error) {
        console.error('rank_progression_schema_install_failed', error);
        return leaderboardError(
          env,
          503,
          'Rank progression is temporarily unavailable.',
          'rank_progression_schema_unavailable',
        );
      }
      if (isRankMatchResultRoute(url.pathname)) {
        return handleRankMatchResultRequest(
          request,
          env as unknown as RankProgressionEnv,
        );
      }
      if (isPublicRankProfileRoute(url.pathname)) {
        return handlePublicRankProfileRequest(
          request,
          env as unknown as RankProgressionEnv,
        );
      }
      if (isRankCountryFlagRoute(url.pathname)) {
        return handleRankCountryFlagRequest(
          request,
          env as unknown as RankCountryFlagEnv,
        );
      }
      return handleRankProgressionRequest(
        request,
        env as unknown as RankProgressionEnv,
      );
    }

    if (
      request.method === 'GET' &&
      url.pathname === '/v1/competitive/leaderboards/hub'
    ) {
      const authorized = await legacyWorker.fetch(request, env as never, ctx);
      if (!authorized.ok) return authorized;
      return new Response(
        JSON.stringify({
          scopes: ['global', 'beginner', 'easy', 'medium', 'hard', 'expert'],
          modes: ['top', 'around_me', 'friends'],
          variants: ['classic9', 'classic16'],
          futureScopes: [
            'country',
            'current_season',
            'daily_tournament',
            'weekend_tournament',
            'countries',
            'clan',
          ],
        }),
        {
          status: 200,
          headers: authorized.headers,
        },
      );
    }

    if (
      request.method === 'GET' &&
      /^\/v1\/competitive\/leaderboards\/[^/]+$/.test(url.pathname)
    ) {
      const scope = decodeURIComponent(url.pathname.split('/')[4] ?? '');
      if (!SUPPORTED_LEADERBOARD_SCOPES.has(scope)) {
        return leaderboardError(env, 400, 'Invalid leaderboard scope.', 'invalid_scope');
      }
    }

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
    if (
      request.method === 'POST' &&
      isFriendNotificationRoute(url.pathname)
    ) {
      return handleFriendNotificationRequest(
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
    try {
      await ensureRuntimeSchema(env);
      await ensureCompetitiveEconomyHardening(env);
    } catch (error) {
      console.error('competitive_economy_hardening_install_failed', error);
      return;
    }
    await legacyWorker.scheduled(event, env as never, ctx);
  },
};

function leaderboardError(
  env: VariantMatchmakingEnv,
  status: number,
  error: string,
  code: string,
): Response {
  const runtimeEnv = env as VariantMatchmakingEnv & { ALLOWED_ORIGIN?: string };
  return new Response(JSON.stringify({ error, code }), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': runtimeEnv.ALLOWED_ORIGIN || '*',
      'access-control-allow-headers':
        'authorization, content-type, x-firebase-appcheck',
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
    },
  });
}
