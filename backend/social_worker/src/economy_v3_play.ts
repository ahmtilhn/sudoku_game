import {
  adsAllowed,
  economyV3State,
  EconomyV3Error,
  insertCoinEvent,
  type EconomyV3Env,
} from './economy_v3_common';
import { CAREER_REWARDS, careerRewardFor } from './economy_v3_policy';
import { markClaimed, prepareRewardClaim, preparedClaim } from './economy_v3_rewards';

export type PlayDifficulty = keyof typeof CAREER_REWARDS;

export function normalizePlayDifficulty(value: unknown): PlayDifficulty {
  const difficulty = String(value ?? '').trim().toLowerCase();
  if (!(difficulty in CAREER_REWARDS)) {
    throw new EconomyV3Error(400, 'Invalid Sudoku difficulty.', 'invalid_difficulty');
  }
  return difficulty as PlayDifficulty;
}

export async function claimPlayReward(
  env: EconomyV3Env,
  playerId: string,
  input: {
    puzzleId: string;
    completionId: string;
    difficulty: PlayDifficulty;
    variant: 'classic9' | 'classic16';
  },
): Promise<Record<string, unknown>> {
  const validPrefixes =
    input.variant === 'classic16'
      ? [`classic16-${input.difficulty}-`]
      : [`generated-${input.difficulty}-`, `career-random-${input.difficulty}-`];
  if (!validPrefixes.some((prefix) => input.puzzleId.startsWith(prefix))) {
    throw new EconomyV3Error(
      400,
      'The Quick Play puzzle does not match the selected mode.',
      'invalid_play_puzzle',
    );
  }

  const amount = CAREER_REWARDS[input.difficulty];
  const inserted = await insertCoinEvent(env, {
    playerId,
    source: 'play_completion',
    // A fresh completion ID is generated for every completed run, so replaying
    // the same puzzle legitimately earns the configured difficulty reward again.
    referenceId: input.completionId,
    amount,
    ledgerReason: 'achievement_reward',
    metadata: {
      mode: 'quick_play',
      variant: input.variant,
      difficulty: input.difficulty,
      puzzleId: input.puzzleId,
      rewardPolicy: 'every_completed_run',
    },
  });

  return {
    granted: inserted,
    amount: inserted ? amount : 0,
    difficulty: input.difficulty,
    variant: input.variant,
    puzzleId: input.puzzleId,
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

  const progress = await env.DB.prepare(
    `SELECT highest_rewarded_level FROM economy_v3_career_progress
     WHERE player_id = ? AND variant = ?`,
  )
    .bind(playerId, input.variant)
    .first<{ highest_rewarded_level: number }>();
  if (Number(progress?.highest_rewarded_level ?? 0) < input.level) {
    throw new EconomyV3Error(
      409,
      'Complete this Career level before doubling its reward.',
      'career_reward_not_earned',
    );
  }

  const amount = careerRewardFor(input.level, input.variant);
  return prepareRewardClaim(env, {
    playerId,
    rewardType: 'career_rewarded_ad',
    rewardKey: `career_double:${input.variant}:${input.level}`,
    amount,
  });
}

export async function confirmCareerDouble(
  env: EconomyV3Env,
  playerId: string,
  token: string,
): Promise<Record<string, unknown>> {
  const claim = await preparedClaim(env, playerId, token, 'career_double:');
  if (claim.status === 'claimed') {
    return { granted: false, amount: 0, ...(await economyV3State(env, playerId)) };
  }

  const amount = Number(claim.amount ?? 0);
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new EconomyV3Error(500, 'Invalid Career double reward.', 'invalid_reward_amount');
  }
  const rewardKey = String(claim.reward_key ?? '');
  const inserted = await insertCoinEvent(env, {
    playerId,
    source: 'career_completion_double',
    referenceId: rewardKey,
    amount,
    ledgerReason: 'career_rewarded_ad',
    metadata: { rewardKey, rewardPolicy: 'career_x2' },
  });
  await markClaimed(env, claim.id);
  return {
    granted: inserted,
    amount: inserted ? amount : 0,
    ...(await economyV3State(env, playerId)),
  };
}
