import {
  EconomyV3Error,
  type EconomyV3Env,
} from './economy_v3_common';

export async function prepareRewardClaim(
  env: EconomyV3Env,
  input: {
    playerId: string;
    rewardType: 'daily_rewarded_ad' | 'career_rewarded_ad';
    rewardKey: string;
    amount: number;
  },
): Promise<Record<string, unknown>> {
  const existing = await env.DB.prepare(
    `SELECT id, status FROM reward_claims
     WHERE player_id = ? AND reward_type = ? AND reward_key = ?`,
  )
    .bind(input.playerId, input.rewardType, input.rewardKey)
    .first<{ id: string; status: string }>();
  if (existing?.status === 'claimed') {
    throw new EconomyV3Error(409, 'This reward was already claimed.', 'reward_claimed');
  }

  const token = crypto.randomUUID();
  const now = new Date();
  const expires = new Date(now.getTime() + 15 * 60 * 1000);
  if (existing) {
    await env.DB.prepare(
      `UPDATE reward_claims
       SET amount = ?, status = 'prepared', verification_token = ?,
           prepared_at = ?, expires_at = ?, ssv_transaction_id = NULL,
           ssv_verified_at = NULL, ssv_ad_unit = NULL
       WHERE id = ?`,
    )
      .bind(input.amount, token, now.toISOString(), expires.toISOString(), existing.id)
      .run();
  } else {
    await env.DB.prepare(
      `INSERT INTO reward_claims (
         id, player_id, reward_type, reward_key, amount, status,
         verification_token, prepared_at, expires_at
       ) VALUES (?, ?, ?, ?, ?, 'prepared', ?, ?, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        input.playerId,
        input.rewardType,
        input.rewardKey,
        input.amount,
        token,
        now.toISOString(),
        expires.toISOString(),
      )
      .run();
  }
  return {
    token,
    rewardType: input.rewardType,
    rewardKey: input.rewardKey,
    amount: input.amount,
    expiresAt: expires.toISOString(),
  };
}

export async function preparedClaim(
  env: EconomyV3Env,
  playerId: string,
  token: string,
  rewardKeyPrefix: string,
): Promise<Record<string, unknown>> {
  const claim = await env.DB.prepare(
    `SELECT * FROM reward_claims
     WHERE player_id = ? AND verification_token = ? LIMIT 1`,
  )
    .bind(playerId, token)
    .first<Record<string, unknown>>();
  if (!claim || !String(claim.reward_key ?? '').startsWith(rewardKeyPrefix)) {
    throw new EconomyV3Error(404, 'Reward preparation not found.', 'reward_not_found');
  }
  if (claim.status === 'claimed') return claim;
  if (claim.status !== 'prepared') {
    throw new EconomyV3Error(409, 'Reward is no longer available.', 'reward_unavailable');
  }
  if (claim.expires_at && Date.parse(String(claim.expires_at)) <= Date.now()) {
    await env.DB.prepare(`UPDATE reward_claims SET status = 'expired' WHERE id = ?`)
      .bind(claim.id)
      .run();
    throw new EconomyV3Error(409, 'Reward confirmation expired.', 'reward_expired');
  }
  return claim;
}

export async function markClaimed(
  env: EconomyV3Env,
  claimId: unknown,
): Promise<void> {
  await env.DB.prepare(
    `UPDATE reward_claims SET status = 'claimed', claimed_at = ?
     WHERE id = ? AND status = 'prepared'`,
  )
    .bind(new Date().toISOString(), String(claimId))
    .run();
}
