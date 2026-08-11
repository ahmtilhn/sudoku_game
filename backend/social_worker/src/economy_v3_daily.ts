import {
  adsAllowed,
  dailyStateRow,
  economyV3State,
  EconomyV3Error,
  insertCoinEvent,
  insertInventoryEvent,
  type EconomyV3Env,
  utcDay,
} from './economy_v3_common';
import { DAILY_REWARD_CALENDAR } from './economy_v3_policy';
import { markClaimed, prepareRewardClaim, preparedClaim } from './economy_v3_rewards';

export async function claimDailyCalendarReward(
  env: EconomyV3Env,
  playerId: string,
): Promise<Record<string, unknown>> {
  const now = new Date();
  const day = utcDay(now);
  const state = await dailyStateRow(env, playerId);
  if (state.last_claim_day === day) {
    return {
      granted: false,
      code: 'already_claimed_today',
      ...(await economyV3State(env, playerId)),
    };
  }

  const sequence = state.claims_total + 1;
  const cycleDay = ((sequence - 1) % DAILY_REWARD_CALENDAR.length) + 1;
  const reward = DAILY_REWARD_CALENDAR[cycleDay - 1];
  let inserted = false;

  if (reward.kind === 'coin') {
    inserted = await insertCoinEvent(env, {
      playerId,
      source: 'daily_calendar',
      referenceId: `sequence:${sequence}`,
      amount: reward.amount,
      ledgerReason: 'daily_login',
      metadata: { sequence, cycleDay, dayKey: day },
    });
  } else {
    inserted = await insertInventoryEvent(env, {
      playerId,
      source: 'daily_calendar_refill',
      referenceId: `sequence:${sequence}`,
      refillDelta: 1,
    });
  }

  await env.DB.prepare(
    `INSERT INTO economy_v3_daily_state (
       player_id, claims_total, last_claim_day, last_claim_sequence,
       last_claim_amount, doubled_sequence, updated_at
     ) VALUES (?, ?, ?, ?, ?, 0, ?)
     ON CONFLICT(player_id) DO UPDATE SET
       claims_total = MAX(economy_v3_daily_state.claims_total, excluded.claims_total),
       last_claim_day = excluded.last_claim_day,
       last_claim_sequence = MAX(economy_v3_daily_state.last_claim_sequence, excluded.last_claim_sequence),
       last_claim_amount = excluded.last_claim_amount,
       updated_at = excluded.updated_at`,
  )
    .bind(
      playerId,
      sequence,
      day,
      sequence,
      reward.kind === 'coin' ? reward.amount : 0,
      now.toISOString(),
    )
    .run();

  // Preserve legacy streak/day bookkeeping without paying the old flat 50 Coin reward.
  await env.DB.prepare(
    `INSERT INTO reward_claims (
       id, player_id, reward_type, reward_key, amount, status, prepared_at, claimed_at
     ) VALUES (?, ?, 'daily_login', ?, ?, 'claimed', ?, ?)
     ON CONFLICT(player_id, reward_type, reward_key) DO NOTHING`,
  )
    .bind(
      crypto.randomUUID(),
      playerId,
      day,
      reward.kind === 'coin' ? reward.amount : 0,
      now.toISOString(),
      now.toISOString(),
    )
    .run();

  return {
    granted: inserted,
    sequence,
    cycleDay,
    reward,
    ...(await economyV3State(env, playerId)),
  };
}

export async function prepareDailyDouble(
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
  const state = await dailyStateRow(env, playerId);
  const day = utcDay();
  if (state.last_claim_day !== day || state.last_claim_amount <= 0) {
    throw new EconomyV3Error(409, 'There is no Coin daily reward to double.', 'daily_double_unavailable');
  }
  if (state.doubled_sequence === state.last_claim_sequence) {
    throw new EconomyV3Error(409, 'This daily reward was already doubled.', 'daily_double_claimed');
  }
  return prepareRewardClaim(env, {
    playerId,
    rewardType: 'daily_rewarded_ad',
    rewardKey: `v3_daily_double:${state.last_claim_sequence}`,
    amount: state.last_claim_amount,
  });
}

export async function confirmDailyDouble(
  env: EconomyV3Env,
  playerId: string,
  token: string,
): Promise<Record<string, unknown>> {
  const claim = await preparedClaim(env, playerId, token, 'v3_daily_double:');
  if (claim.status === 'claimed') {
    return { granted: false, amount: 0, ...(await economyV3State(env, playerId)) };
  }
  const sequence = Number(String(claim.reward_key).split(':').pop());
  const state = await dailyStateRow(env, playerId);
  if (
    !Number.isInteger(sequence) ||
    sequence !== state.last_claim_sequence ||
    state.last_claim_day !== utcDay()
  ) {
    throw new EconomyV3Error(409, 'The daily reward is no longer eligible for doubling.', 'daily_double_stale');
  }
  const amount = Number(claim.amount ?? 0);
  const inserted = await insertCoinEvent(env, {
    playerId,
    source: 'daily_calendar_double',
    referenceId: `sequence:${sequence}`,
    amount,
    ledgerReason: 'daily_rewarded_ad',
    metadata: { sequence, dayKey: utcDay() },
  });
  await markClaimed(env, claim.id);
  await env.DB.prepare(
    `UPDATE economy_v3_daily_state
     SET doubled_sequence = MAX(doubled_sequence, ?), updated_at = ?
     WHERE player_id = ?`,
  )
    .bind(sequence, new Date().toISOString(), playerId)
    .run();
  return {
    granted: inserted,
    amount: inserted ? amount : 0,
    ...(await economyV3State(env, playerId)),
  };
}
