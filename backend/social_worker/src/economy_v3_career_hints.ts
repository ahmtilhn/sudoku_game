import {
  adsAllowed,
  economyV3State,
  EconomyV3Error,
  insertCoinEvent,
  type EconomyV3Env,
  utcDay,
} from './economy_v3_common';
import {
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

  // Career completion rewards are intentionally uncapped. A player earns the
  // full configured reward for every first-time level completion, regardless
  // of how many Career levels they finish in the same UTC day.
  const amount = requested;
  const inserted = await insertCoinEvent(env, {
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
      dailyCap: null,
      rewardPolicy: 'uncapped',
    },
  });

  const day = utcDay();
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
    // Keep the daily aggregate for analytics/state reporting only. It no longer
    // limits how many Coins Career mode can award in a day.
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
    capped: false,
    difficulty,
    level: input.level,
    variant: input.variant,
    ...(await economyV3State(env, playerId)),
  };
}

export async function prepareCareerDouble(
  env: EconomyV3Env,
  playerId: string,
  input: { level: number; variant: 'classic9' | 'classic16' },
): Promise<Record<string, unknown>> {
  if (!(await adsAllowed(env, playerId))) {
    throw new EconomyV3Error(
      403,
      'Rewarded ads are disabled for the No Ads entitlement.',
      'ads_disabled_entitlement',
    );
  }

  const baseReference = `${input.variant}:${input.level}`;
  const completion = await env.DB.prepare(
    `SELECT amount FROM economy_v3_coin_events
     WHERE player_id = ? AND source = 'career_completion' AND reference_id = ?
     LIMIT 1`,
  )
    .bind(playerId, baseReference)
    .first<{ amount: number }>();
  const amount = Number(completion?.amount ?? 0);
  if (amount <= 0) {
    throw new EconomyV3Error(
      409,
      'The Career completion reward must be earned before it can be doubled.',
      'career_reward_not_earned',
    );
  }

  return prepareRewardClaim(env, {
    playerId,
    rewardType: 'career_rewarded_ad',
    rewardKey: `v3_career_double:${input.variant}:${input.level}`,
    amount,
  });
}

export async function confirmCareerDouble(
  env: EconomyV3Env,
  playerId: string,
  token: string,
): Promise<Record<string, unknown>> {
  const claim = await preparedClaim(env, playerId, token, 'v3_career_double:');
  if (claim.status === 'claimed') {
    return {
      granted: false,
      amount: 0,
      replay: true,
      ...(await economyV3State(env, playerId)),
    };
  }

  const rewardKey = String(claim.reward_key ?? '');
  const amount = Number(claim.amount ?? 0);
  if (amount <= 0) {
    throw new EconomyV3Error(409, 'Invalid Career double reward.', 'invalid_reward_amount');
  }

  const inserted = await insertCoinEvent(env, {
    playerId,
    source: 'career_double_rewarded_ad',
    referenceId: rewardKey,
    amount,
    ledgerReason: 'career_rewarded_ad',
    metadata: {
      rewardKey,
      rewardPolicy: 'career_completion_x2',
    },
  });
  await markClaimed(env, claim.id);

  return {
    granted: inserted,
    amount: inserted ? amount : 0,
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
