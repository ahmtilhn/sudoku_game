import {
  adsAllowed,
  economyV3State,
  EconomyV3Error,
  insertCoinEvent,
  type EconomyV3Env,
  utcDay,
} from './economy_v3_common';
import {
  CAREER_DAILY_COIN_CAP,
  HINT_COIN_COST,
  HINT_REFILL_SIZE,
  careerDifficulty,
  careerRewardFor,
} from './economy_v3_policy';
import { markClaimed, prepareRewardClaim, preparedClaim } from './economy_v3_rewards';

export async function claimCareerReward(
  env: EconomyV3Env,
  playerId: string,
  input: { level: number; variant: 'classic9' | 'classic16' },
): Promise<Record<string, unknown>> {
  const difficulty = careerDifficulty(input.level, input.variant);
  const requested = careerRewardFor(input.level, input.variant);
  const progress = await env.DB.prepare(
    `SELECT highest_rewarded_level FROM economy_v3_career_progress
     WHERE player_id = ? AND variant = ?`,
  )
    .bind(playerId, input.variant)
    .first<{ highest_rewarded_level: number }>();
  const highest = Number(progress?.highest_rewarded_level ?? 0);

  if (input.level <= highest) {
    return {
      granted: false,
      amount: 0,
      replay: true,
      difficulty,
      level: input.level,
      variant: input.variant,
      ...(await economyV3State(env, playerId)),
    };
  }
  // Existing installations may start V3 at their current local level. Once a
  // server progress row exists, level claims must be strictly sequential.
  if (progress && input.level !== highest + 1) {
    throw new EconomyV3Error(
      409,
      'Career rewards must be claimed in level order.',
      'career_sequence_gap',
    );
  }

  const day = utcDay();
  const daily = await env.DB.prepare(
    `SELECT coins_earned FROM economy_v3_career_daily
     WHERE player_id = ? AND day_key = ?`,
  )
    .bind(playerId, day)
    .first<{ coins_earned: number }>();
  const earned = Number(daily?.coins_earned ?? 0);
  const remaining = Math.max(0, CAREER_DAILY_COIN_CAP - earned);
  const amount = Math.min(requested, remaining);
  let inserted = false;

  if (amount > 0) {
    inserted = await insertCoinEvent(env, {
      playerId,
      source: 'career_completion',
      referenceId: `${input.variant}:${input.level}`,
      amount,
      // Kept inside the existing production ledger CHECK. economySource in
      // metadata carries the exact V3 semantic reason.
      ledgerReason: 'achievement_reward',
      metadata: {
        variant: input.variant,
        level: input.level,
        difficulty,
        requested,
        dailyCap: CAREER_DAILY_COIN_CAP,
      },
    });
  }

  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO economy_v3_career_progress (
         player_id, variant, highest_rewarded_level, updated_at
       ) VALUES (?, ?, ?, ?)
       ON CONFLICT(player_id, variant) DO UPDATE SET
         highest_rewarded_level = MAX(
           economy_v3_career_progress.highest_rewarded_level,
           excluded.highest_rewarded_level
         ),
         updated_at = excluded.updated_at`,
    ).bind(playerId, input.variant, input.level, now),
    env.DB.prepare(
      `INSERT INTO economy_v3_career_daily (player_id, day_key, coins_earned, updated_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(player_id, day_key) DO UPDATE SET
         coins_earned = economy_v3_career_daily.coins_earned + ?,
         updated_at = excluded.updated_at`,
    ).bind(playerId, day, inserted ? amount : 0, now, inserted ? amount : 0),
  ]);

  return {
    granted: inserted,
    amount: inserted ? amount : 0,
    requestedAmount: requested,
    capped: amount < requested,
    difficulty,
    level: input.level,
    variant: input.variant,
    ...(await economyV3State(env, playerId)),
  };
}

export async function purchaseHint(
  env: EconomyV3Env,
  playerId: string,
  requestId: string,
): Promise<Record<string, unknown>> {
  const inserted = await insertCoinEvent(env, {
    playerId,
    source: 'hint_purchase',
    referenceId: requestId,
    amount: -HINT_COIN_COST,
    ledgerReason: 'career_continue',
    metadata: { item: 'hint', coinCost: HINT_COIN_COST },
  });
  return {
    grantedHint: inserted,
    spent: inserted ? HINT_COIN_COST : 0,
    ...(await economyV3State(env, playerId)),
  };
}

export async function prepareHintReward(
  env: EconomyV3Env,
  playerId: string,
): Promise<Record<string, unknown>> {
  if (!(await adsAllowed(env, playerId))) {
    throw new EconomyV3Error(
      403,
      'Rewarded ads are disabled for the No Ads entitlement.',
      'ads_disabled_entitlement',
    );
  }
  return prepareRewardClaim(env, {
    playerId,
    rewardType: 'career_rewarded_ad',
    rewardKey: `v3_hint:${crypto.randomUUID()}`,
    amount: 1,
  });
}

export async function confirmHintReward(
  env: EconomyV3Env,
  playerId: string,
  token: string,
): Promise<Record<string, unknown>> {
  const claim = await preparedClaim(env, playerId, token, 'v3_hint:');
  if (claim.status === 'claimed') {
    return { grantedHint: false, ...(await economyV3State(env, playerId)) };
  }
  await markClaimed(env, claim.id);
  return { grantedHint: true, ...(await economyV3State(env, playerId)) };
}

export async function consumeHintRefill(
  env: EconomyV3Env,
  playerId: string,
): Promise<Record<string, unknown>> {
  const result = await env.DB.prepare(
    `UPDATE economy_v3_inventory
     SET hint_refills = hint_refills - 1, updated_at = ?
     WHERE player_id = ? AND hint_refills > 0`,
  )
    .bind(new Date().toISOString(), playerId)
    .run();
  const consumed = (result.meta.changes ?? 0) > 0;
  return {
    consumed,
    refillSize: consumed ? HINT_REFILL_SIZE : 0,
    ...(await economyV3State(env, playerId)),
  };
}
