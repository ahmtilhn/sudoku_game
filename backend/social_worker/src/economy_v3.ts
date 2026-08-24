import { assertProductionRewardConfirmedBySsv } from './admob_ssv';
import {
  economyV3State,
  errorResponse,
  json,
  EconomyV3Error,
  positiveInt,
  prepareEconomyV3Request,
  readJson,
  requiredString,
  type EconomyV3Env,
  type LegacyFetch,
} from './economy_v3_common';
import {
  claimDailyCalendarReward,
  confirmDailyDouble,
  prepareDailyDouble,
} from './economy_v3_daily';
import {
  claimCareerReward,
  confirmHintReward,
  consumeHintRefill,
  prepareHintReward,
  purchaseHint,
} from './economy_v3_career_hints';
import { normalizeVariant } from './economy_v3_policy';
import {
  claimPlayReward,
  confirmCareerDouble,
  normalizePlayDifficulty,
  prepareCareerDouble,
} from './economy_v3_play';
import {
  confirmDuelRecovery,
  dismissDuelRecovery,
  prepareDuelRecovery,
} from './economy_v3_recovery';

const LEGACY_REWARD_ROUTES = new Set([
  '/v1/rewards/daily-login/claim',
  '/v1/rewards/daily-ad/prepare',
  '/v1/rewards/daily-ad/confirm',
  '/v1/rewards/career-ad/prepare',
  '/v1/rewards/career-ad/confirm',
]);

type SsvVerificationRequest = Parameters<
  typeof assertProductionRewardConfirmedBySsv
>[0];

function cloneForSsv(request: Request): SsvVerificationRequest {
  return request.clone() as unknown as SsvVerificationRequest;
}

export function isEconomyV3Route(pathname: string): boolean {
  return pathname === '/v1/economy/v3/state' || pathname.startsWith('/v1/economy/v3/');
}

export function isLegacyEconomyRewardRoute(pathname: string): boolean {
  return LEGACY_REWARD_ROUTES.has(pathname);
}

export function legacyEconomyRewardResponse(env: EconomyV3Env): Response {
  return json(env, 410, {
    error: 'This reward flow has moved to Economy V3.',
    code: 'economy_v3_required',
  });
}

export async function handleEconomyV3Request(
  request: Request,
  env: EconomyV3Env,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
): Promise<Response> {
  void ctx;
  try {
    const playerId = await prepareEconomyV3Request(request, env, legacyFetch);
    const url = new URL(request.url);

    if (url.pathname === '/v1/economy/v3/state' && request.method === 'GET') {
      return json(env, 200, await economyV3State(env, playerId));
    }
    if (url.pathname === '/v1/economy/v3/daily/claim' && request.method === 'POST') {
      return json(env, 200, await claimDailyCalendarReward(env, playerId));
    }
    if (
      url.pathname === '/v1/economy/v3/daily/double/prepare' &&
      request.method === 'POST'
    ) {
      return json(env, 200, await prepareDailyDouble(env, playerId));
    }
    if (
      url.pathname === '/v1/economy/v3/daily/double/confirm' &&
      request.method === 'POST'
    ) {
      await assertProductionRewardConfirmedBySsv(cloneForSsv(request), env);
      const body = await readJson(request);
      return json(
        env,
        200,
        await confirmDailyDouble(env, playerId, requiredString(body.token, 'token')),
      );
    }
    if (url.pathname === '/v1/economy/v3/career/claim' && request.method === 'POST') {
      const body = await readJson(request);
      let variant: 'classic9' | 'classic16';
      try {
        variant = normalizeVariant(body.variant);
      } catch {
        throw new EconomyV3Error(400, 'Invalid Sudoku variant.', 'invalid_variant');
      }
      return json(
        env,
        200,
        await claimCareerReward(env, playerId, {
          level: positiveInt(body.level, 'level'),
          variant,
        }),
      );
    }
    if (
      url.pathname === '/v1/economy/v3/career/double/prepare' &&
      request.method === 'POST'
    ) {
      const body = await readJson(request);
      let variant: 'classic9' | 'classic16';
      try {
        variant = normalizeVariant(body.variant);
      } catch {
        throw new EconomyV3Error(400, 'Invalid Sudoku variant.', 'invalid_variant');
      }
      return json(
        env,
        200,
        await prepareCareerDouble(env, playerId, {
          level: positiveInt(body.level, 'level'),
          variant,
        }),
      );
    }
    if (
      url.pathname === '/v1/economy/v3/career/double/confirm' &&
      request.method === 'POST'
    ) {
      await assertProductionRewardConfirmedBySsv(cloneForSsv(request), env);
      const body = await readJson(request);
      return json(
        env,
        200,
        await confirmCareerDouble(env, playerId, requiredString(body.token, 'token')),
      );
    }
    if (url.pathname === '/v1/economy/v3/play/claim' && request.method === 'POST') {
      const body = await readJson(request);
      let variant: 'classic9' | 'classic16';
      try {
        variant = normalizeVariant(body.variant);
      } catch {
        throw new EconomyV3Error(400, 'Invalid Sudoku variant.', 'invalid_variant');
      }
      return json(
        env,
        200,
        await claimPlayReward(env, playerId, {
          puzzleId: requiredString(body.puzzleId, 'puzzleId', 192),
          completionId: requiredString(body.completionId, 'completionId', 128),
          difficulty: normalizePlayDifficulty(body.difficulty),
          variant,
        }),
      );
    }
    if (url.pathname === '/v1/economy/v3/hints/purchase' && request.method === 'POST') {
      const body = await readJson(request);
      return json(
        env,
        200,
        await purchaseHint(env, playerId, requiredString(body.requestId, 'requestId', 128)),
      );
    }
    if (
      url.pathname === '/v1/economy/v3/hints/reward/prepare' &&
      request.method === 'POST'
    ) {
      return json(env, 200, await prepareHintReward(env, playerId));
    }
    if (
      url.pathname === '/v1/economy/v3/hints/reward/confirm' &&
      request.method === 'POST'
    ) {
      await assertProductionRewardConfirmedBySsv(cloneForSsv(request), env);
      const body = await readJson(request);
      return json(
        env,
        200,
        await confirmHintReward(env, playerId, requiredString(body.token, 'token')),
      );
    }
    if (
      url.pathname === '/v1/economy/v3/hints/refill/consume' &&
      request.method === 'POST'
    ) {
      return json(env, 200, await consumeHintRefill(env, playerId));
    }
    if (
      url.pathname === '/v1/economy/v3/recovery/prepare' &&
      request.method === 'POST'
    ) {
      const body = await readJson(request);
      return json(
        env,
        200,
        await prepareDuelRecovery(env, playerId, requiredString(body.matchId, 'matchId')),
      );
    }
    if (
      url.pathname === '/v1/economy/v3/recovery/confirm' &&
      request.method === 'POST'
    ) {
      await assertProductionRewardConfirmedBySsv(cloneForSsv(request), env);
      const body = await readJson(request);
      return json(
        env,
        200,
        await confirmDuelRecovery(env, playerId, requiredString(body.token, 'token')),
      );
    }
    if (
      url.pathname === '/v1/economy/v3/recovery/dismiss' &&
      request.method === 'POST'
    ) {
      const body = await readJson(request);
      return json(
        env,
        200,
        await dismissDuelRecovery(env, playerId, requiredString(body.matchId, 'matchId')),
      );
    }

    return json(env, 404, { error: 'Route not found.', code: 'route_not_found' });
  } catch (error) {
    return errorResponse(env, error);
  }
}
