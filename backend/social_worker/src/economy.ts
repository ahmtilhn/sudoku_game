import { applyDailyRewardState, unlockAchievement } from './competitive';

export const STARTER_COINS = 1000;
export const ENTRY_FEES: Readonly<Record<DuelDifficultyKey, number>> = Object.freeze({
  beginner: 100,
  easy: 150,
  medium: 250,
  hard: 400,
  expert: 650,
});
export const MINIMUM_ONLINE_BALANCE = ENTRY_FEES.beginner;
export const MATCH_ENTRY_FEE = MINIMUM_ONLINE_BALANCE;
export const MATCH_POT = MINIMUM_ONLINE_BALANCE * 2;
export const DAILY_LOGIN_REWARD = 50;
export const DAILY_AD_REWARD = 50;
export const CAREER_AD_REWARD = 25;
export const REMATCH_WINDOW_MS = 10_000;
export const DEBUG_UNLIMITED_COINS_BALANCE = 999999999;
export const NO_ADS_PRODUCT_ID = 'no_ads';

export type DuelDifficultyKey = 'beginner' | 'easy' | 'medium' | 'hard' | 'expert';

export const COIN_PRODUCTS: Readonly<Record<string, number>> = Object.freeze({
  coins_100: 100,
  coins_500: 500,
  coins_1000: 1000,
  coins_5000: 5000,
  coins_10000: 10000,
  coins_50000: 50000,
  coins_100000: 100000,
});

export function entryFeeForDifficulty(difficulty: string): number {
  const fee = ENTRY_FEES[difficulty as DuelDifficultyKey];
  if (!fee) throw new EconomyError(400, 'Invalid difficulty.', 'invalid_difficulty');
  return fee;
}

export function potForDifficulty(difficulty: string): number {
  return entryFeeForDifficulty(difficulty) * 2;
}

export interface EconomyEnv {
  DB: D1Database;
  MATCHMAKING_QUEUE?: DurableObjectNamespace;
  ENVIRONMENT?: string;
  ALLOW_TEST_PURCHASE_GRANTS?: string;
  DEBUG_UNLIMITED_COINS?: string;
  FCM_PROJECT_ID?: string;
  FCM_CLIENT_EMAIL?: string;
  FCM_PRIVATE_KEY?: string;
}

export class EconomyError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
  ) {
    super(message);
  }
}

export type FundedMatchInput = {
  matchId: string;
  roomId: string;
  challengeId: string | null;
  mode: 'friendly' | 'ranked';
  difficulty: string;
  playerAId: string;
  playerBId: string;
  now: string;
};

export type RematchRow = {
  id: string;
  previous_match_id: string;
  sender_id: string;
  recipient_id: string;
  difficulty: string;
  status: string;
  room_id: string | null;
  created_at: string;
  updated_at: string;
  expires_at: string;
  responded_at: string | null;
};

export async function ensureStarterGrant(
  env: EconomyEnv,
  playerId: string,
): Promise<number> {
  const idempotencyKey = `starter_grant:${playerId}`;
  const existing = await env.DB.prepare(
    'SELECT balance_after FROM coin_ledger WHERE idempotency_key = ? LIMIT 1',
  )
    .bind(idempotencyKey)
    .first<{ balance_after: number | null }>();
  if (!existing) {
    const now = new Date().toISOString();
    const inserted = await env.DB.prepare(
      `INSERT OR IGNORE INTO coin_ledger (
         id, player_id, amount, balance_after, reason,
         reference_type, reference_id, idempotency_key, metadata_json, created_at
       ) VALUES (?, ?, ?, NULL, 'starter_grant', 'player', ?, ?, ?, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        playerId,
        STARTER_COINS,
        playerId,
        idempotencyKey,
        JSON.stringify({ oncePerAccount: true }),
        now,
      )
      .run();

    if ((inserted.meta.changes ?? 0) > 0) {
      await env.DB.batch([
        env.DB.prepare(
          'UPDATE players SET online_coins = online_coins + ?, updated_at = ? WHERE id = ?',
        ).bind(STARTER_COINS, now, playerId),
        env.DB.prepare(
          `UPDATE coin_ledger
           SET balance_after = (SELECT online_coins FROM players WHERE id = ?)
           WHERE idempotency_key = ?`,
        ).bind(playerId, idempotencyKey),
      ]);
    }
  }
  await applyDebugUnlimitedCoins(env, playerId);
  return coinBalance(env, playerId);
}

export async function walletSnapshot(
  env: EconomyEnv,
  playerId: string,
): Promise<Record<string, unknown>> {
  const balance = await ensureStarterGrant(env, playerId);
  const day = utcDay();
  const [dailyLogin, dailyAd] = await Promise.all([
    env.DB.prepare(
      `SELECT status FROM reward_claims
       WHERE player_id = ? AND reward_type = 'daily_login' AND reward_key = ?`,
    )
      .bind(playerId, day)
      .first<{ status: string }>(),
    env.DB.prepare(
      `SELECT status FROM reward_claims
       WHERE player_id = ? AND reward_type = 'daily_rewarded_ad' AND reward_key = ?`,
    )
      .bind(playerId, day)
      .first<{ status: string }>(),
  ]);
  const nextReset = new Date(`${day}T00:00:00.000Z`);
  nextReset.setUTCDate(nextReset.getUTCDate() + 1);
  return {
    balance,
    canEnterOnline: balance >= MINIMUM_ONLINE_BALANCE,
    minimumOnlineBalance: MINIMUM_ONLINE_BALANCE,
    entryFees: ENTRY_FEES,
    entitlements: await entitlementSnapshot(env, playerId),
    starterGrant: STARTER_COINS,
    dailyLogin: {
      amount: DAILY_LOGIN_REWARD,
      available: dailyLogin?.status !== 'claimed',
    },
    dailyRewardedAd: {
      amount: DAILY_AD_REWARD,
      available: dailyAd?.status !== 'claimed',
    },
    nextDailyResetAt: nextReset.toISOString(),
  };
}

export async function ledgerPage(
  env: EconomyEnv,
  playerId: string,
  limit = 50,
): Promise<Record<string, unknown>> {
  await ensureStarterGrant(env, playerId);
  const safeLimit = Math.max(1, Math.min(100, Math.trunc(limit)));
  const rows = await env.DB.prepare(
    `SELECT id, amount, balance_after, reason, reference_type, reference_id,
            metadata_json, created_at
     FROM coin_ledger
     WHERE player_id = ?
     ORDER BY created_at DESC
     LIMIT ?`,
  )
    .bind(playerId, safeLimit)
    .all<Record<string, unknown>>();
  return {
    entries: rows.results.map((row) => ({
      id: row.id,
      amount: row.amount,
      balanceAfter: row.balance_after,
      reason: row.reason,
      referenceType: row.reference_type,
      referenceId: row.reference_id,
      metadata: parseJsonObject(row.metadata_json),
      createdAt: row.created_at,
    })),
  };
}

export async function claimDailyLogin(
  env: EconomyEnv,
  playerId: string,
): Promise<Record<string, unknown>> {
  await ensureStarterGrant(env, playerId);
  const day = utcDay();
  const idempotencyKey = `daily_login:${playerId}:${day}`;
  const granted = await grantCoinsOnce(env, {
    playerId,
    amount: DAILY_LOGIN_REWARD,
    reason: 'daily_login',
    referenceType: 'day',
    referenceId: day,
    idempotencyKey,
    metadata: { utcDay: day },
  });
  await env.DB.prepare(
    `INSERT INTO reward_claims (
       id, player_id, reward_type, reward_key, amount, status,
       prepared_at, claimed_at
     ) VALUES (?, ?, 'daily_login', ?, ?, 'claimed', ?, ?)
     ON CONFLICT(player_id, reward_type, reward_key) DO UPDATE SET
       status = 'claimed', claimed_at = COALESCE(reward_claims.claimed_at, excluded.claimed_at)`,
  )
    .bind(
      crypto.randomUUID(),
      playerId,
      day,
      DAILY_LOGIN_REWARD,
      new Date().toISOString(),
      new Date().toISOString(),
    )
    .run();
  const dailyState = await applyDailyRewardState(env, playerId);
  return {
    granted,
    amount: granted ? DAILY_LOGIN_REWARD : 0,
    dailyRewardState: dailyState,
    ...(await walletSnapshot(env, playerId)),
  };
}

export async function prepareAdReward(
  env: EconomyEnv,
  playerId: string,
  kind: 'daily_rewarded_ad' | 'career_rewarded_ad',
): Promise<Record<string, unknown>> {
  await ensureStarterGrant(env, playerId);
  const now = new Date();
  const rewardKey = kind === 'daily_rewarded_ad' ? utcDay(now) : crypto.randomUUID();
  const amount = kind === 'daily_rewarded_ad' ? DAILY_AD_REWARD : CAREER_AD_REWARD;
  const existing = await env.DB.prepare(
    `SELECT status FROM reward_claims
     WHERE player_id = ? AND reward_type = ? AND reward_key = ?`,
  )
    .bind(playerId, kind, rewardKey)
    .first<{ status: string }>();
  if (existing?.status === 'claimed') {
    throw new EconomyError(409, 'This reward has already been claimed.', 'reward_claimed');
  }
  const token = crypto.randomUUID();
  const expires = new Date(now.getTime() + 15 * 60 * 1000);
  await env.DB.prepare(
    `INSERT INTO reward_claims (
       id, player_id, reward_type, reward_key, amount, status,
       verification_token, prepared_at, expires_at
     ) VALUES (?, ?, ?, ?, ?, 'prepared', ?, ?, ?)
     ON CONFLICT(player_id, reward_type, reward_key) DO UPDATE SET
       verification_token = CASE
         WHEN reward_claims.status = 'claimed' THEN reward_claims.verification_token
         ELSE excluded.verification_token END,
       prepared_at = CASE
         WHEN reward_claims.status = 'claimed' THEN reward_claims.prepared_at
         ELSE excluded.prepared_at END,
       expires_at = CASE
         WHEN reward_claims.status = 'claimed' THEN reward_claims.expires_at
         ELSE excluded.expires_at END`,
  )
    .bind(
      crypto.randomUUID(),
      playerId,
      kind,
      rewardKey,
      amount,
      token,
      now.toISOString(),
      expires.toISOString(),
    )
    .run();
  return { token, rewardType: kind, rewardKey, amount, expiresAt: expires.toISOString() };
}

export async function confirmAdReward(
  env: EconomyEnv,
  playerId: string,
  token: string,
): Promise<Record<string, unknown>> {
  const claim = await env.DB.prepare(
    `SELECT * FROM reward_claims
     WHERE player_id = ? AND verification_token = ? LIMIT 1`,
  )
    .bind(playerId, token)
    .first<Record<string, unknown>>();
  if (!claim) throw new EconomyError(404, 'Reward preparation not found.', 'reward_not_found');
  if (claim.status === 'claimed') {
    return { granted: false, amount: 0, ...(await walletSnapshot(env, playerId)) };
  }
  if (claim.status !== 'prepared') {
    throw new EconomyError(409, 'Reward is no longer available.', 'reward_unavailable');
  }
  if (claim.expires_at && Date.parse(String(claim.expires_at)) <= Date.now()) {
    await env.DB.prepare('UPDATE reward_claims SET status = ? WHERE id = ?')
      .bind('expired', claim.id)
      .run();
    throw new EconomyError(409, 'Reward confirmation expired.', 'reward_expired');
  }
  const reason = String(claim.reward_type) as
    | 'daily_rewarded_ad'
    | 'career_rewarded_ad';
  const amount = Number(claim.amount);
  const idempotencyKey = `${reason}:${playerId}:${String(claim.reward_key)}`;
  const granted = await grantCoinsOnce(env, {
    playerId,
    amount,
    reason,
    referenceType: 'reward_claim',
    referenceId: String(claim.id),
    idempotencyKey,
    metadata: { rewardKey: claim.reward_key },
  });
  await env.DB.prepare(
    `UPDATE reward_claims SET status = 'claimed', claimed_at = ?
     WHERE id = ? AND status = 'prepared'`,
  )
    .bind(new Date().toISOString(), claim.id)
    .run();
  return { granted, amount: granted ? amount : 0, ...(await walletSnapshot(env, playerId)) };
}

export async function claimAchievementReward(
  env: EconomyEnv,
  playerId: string,
  achievementId: string,
): Promise<Record<string, unknown>> {
  const definition = achievementDefinition(achievementId);
  await verifyAchievement(env, playerId, definition.requirement);
  await unlockAchievement(env, { playerId, achievementId });
  const idempotencyKey = `achievement:${playerId}:${achievementId}`;
  const granted = await grantCoinsOnce(env, {
    playerId,
    amount: definition.amount,
    reason: 'achievement_reward',
    referenceType: 'achievement',
    referenceId: achievementId,
    idempotencyKey,
    metadata: { tier: definition.tier },
  });
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO reward_claims (
       id, player_id, reward_type, reward_key, amount, status,
       prepared_at, claimed_at
     ) VALUES (?, ?, 'achievement_reward', ?, ?, 'claimed', ?, ?)
     ON CONFLICT(player_id, reward_type, reward_key) DO NOTHING`,
  )
    .bind(
      crypto.randomUUID(),
      playerId,
      achievementId,
      definition.amount,
      now,
      now,
    )
    .run();
  return {
    granted,
    amount: granted ? definition.amount : 0,
    achievementId,
    ...(await walletSnapshot(env, playerId)),
  };
}

export async function spendCareerContinue(
  env: EconomyEnv,
  playerId: string,
  requestId: string,
): Promise<Record<string, unknown>> {
  const amount = 25;
  await ensureStarterGrant(env, playerId);
  const key = `career_continue:${playerId}:${requestId}`;
  const existing = await env.DB.prepare(
    'SELECT 1 FROM coin_ledger WHERE idempotency_key = ? LIMIT 1',
  )
    .bind(key)
    .first();
  if (!existing) {
    const balance = await coinBalance(env, playerId);
    if (balance < amount) {
      throw new EconomyError(409, 'Not enough Coins.', 'insufficient_coins');
    }
    const now = new Date().toISOString();
    await env.DB.batch([
      env.DB.prepare(
        'UPDATE players SET online_coins = online_coins - ?, updated_at = ? WHERE id = ? AND online_coins >= ?',
      ).bind(amount, now, playerId, amount),
      env.DB.prepare(
        `INSERT OR IGNORE INTO coin_ledger (
           id, player_id, amount, balance_after, reason,
           reference_type, reference_id, idempotency_key, metadata_json, created_at
         ) VALUES (?, ?, ?, (SELECT online_coins FROM players WHERE id = ?),
                   'career_continue', 'request', ?, ?, '{}', ?)`,
      ).bind(crypto.randomUUID(), playerId, -amount, playerId, requestId, key, now),
    ]);
  }
  return { spent: true, amount, ...(await walletSnapshot(env, playerId)) };
}

export async function createFundedMatch(
  env: EconomyEnv,
  input: FundedMatchInput,
): Promise<void> {
  if (input.playerAId === input.playerBId) {
    throw new EconomyError(400, 'A match requires two different players.');
  }
  const existing = await env.DB.prepare(
    'SELECT id FROM matches WHERE id = ? OR room_id = ? LIMIT 1',
  )
    .bind(input.matchId, input.roomId)
    .first();
  if (existing) return;

  await Promise.all([
    ensureStarterGrant(env, input.playerAId),
    ensureStarterGrant(env, input.playerBId),
  ]);
  const [aBalance, bBalance] = await Promise.all([
    coinBalance(env, input.playerAId),
    coinBalance(env, input.playerBId),
  ]);
  const entryFee = entryFeeForDifficulty(input.difficulty);
  const pot = entryFee * 2;
  if (aBalance < entryFee || bBalance < entryFee) {
    throw new EconomyError(
      409,
      `Both players need at least ${entryFee} Coins.`,
      'insufficient_coins',
    );
  }

  const aKey = `match_entry:${input.matchId}:${input.playerAId}`;
  const bKey = `match_entry:${input.matchId}:${input.playerBId}`;
  await env.DB.batch([
    env.DB.prepare(
      'UPDATE players SET online_coins = online_coins - ?, updated_at = ? WHERE id = ? AND online_coins >= ?',
    ).bind(entryFee, input.now, input.playerAId, entryFee),
    env.DB.prepare(
      `INSERT INTO coin_ledger (
         id, player_id, amount, balance_after, reason,
         reference_type, reference_id, idempotency_key, metadata_json, created_at
       ) VALUES (?, ?, ?, (SELECT online_coins FROM players WHERE id = ?),
                 'match_entry', 'match', ?, ?, ?, ?)`,
    ).bind(
      crypto.randomUUID(),
      input.playerAId,
      -entryFee,
      input.playerAId,
      input.matchId,
      aKey,
      JSON.stringify({ entryFee, pot }),
      input.now,
    ),
    env.DB.prepare(
      'UPDATE players SET online_coins = online_coins - ?, updated_at = ? WHERE id = ? AND online_coins >= ?',
    ).bind(entryFee, input.now, input.playerBId, entryFee),
    env.DB.prepare(
      `INSERT INTO coin_ledger (
         id, player_id, amount, balance_after, reason,
         reference_type, reference_id, idempotency_key, metadata_json, created_at
       ) VALUES (?, ?, ?, (SELECT online_coins FROM players WHERE id = ?),
                 'match_entry', 'match', ?, ?, ?, ?)`,
    ).bind(
      crypto.randomUUID(),
      input.playerBId,
      -entryFee,
      input.playerBId,
      input.matchId,
      bKey,
      JSON.stringify({ entryFee, pot }),
      input.now,
    ),
    env.DB.prepare(
      `INSERT INTO matches (
         id, room_id, challenge_id, mode, difficulty, status,
         player_a_id, player_b_id, created_at, updated_at
       ) VALUES (?, ?, ?, ?, ?, 'waiting', ?, ?, ?, ?)`,
    ).bind(
      input.matchId,
      input.roomId,
      input.challengeId,
      input.mode,
      input.difficulty,
      input.playerAId,
      input.playerBId,
      input.now,
      input.now,
    ),
    env.DB.prepare(
      `INSERT INTO match_coin_escrow (
         match_id, player_a_id, player_b_id, player_a_amount,
         player_b_amount, pot_amount, status, funded_at
       ) VALUES (?, ?, ?, ?, ?, ?, 'funded', ?)`,
    ).bind(input.matchId, input.playerAId, input.playerBId, entryFee, entryFee, pot, input.now),
    env.DB.prepare(
      'DELETE FROM ranked_queue WHERE player_id IN (?, ?)',
    ).bind(input.playerAId, input.playerBId),
  ]);
}

export async function createRematchInvitation(
  env: EconomyEnv,
  senderId: string,
  previousMatchId: string,
): Promise<Record<string, unknown>> {
  const match = await env.DB.prepare(
    `SELECT id, difficulty, status, player_a_id, player_b_id
     FROM matches WHERE id = ? LIMIT 1`,
  )
    .bind(previousMatchId)
    .first<{
      id: string;
      difficulty: string;
      status: string;
      player_a_id: string;
      player_b_id: string;
    }>();
  if (!match) throw new EconomyError(404, 'Completed match not found.');
  if (!['completed', 'forfeited', 'cancelled', 'abandoned'].includes(match.status)) {
    throw new EconomyError(409, 'The match has not finished yet.');
  }
  const recipientId = match.player_a_id === senderId
    ? match.player_b_id
    : match.player_b_id === senderId
      ? match.player_a_id
      : null;
  if (!recipientId) throw new EconomyError(403, 'You are not a participant in this match.');
  const balance = await ensureStarterGrant(env, senderId);
  const entryFee = entryFeeForDifficulty(match.difficulty);
  if (balance < entryFee) {
    throw new EconomyError(
      409,
      `You need at least ${entryFee} Coins to request a rematch.`,
      'insufficient_coins',
    );
  }

  const now = new Date();
  const expires = new Date(now.getTime() + REMATCH_WINDOW_MS);
  await env.DB.prepare(
    `UPDATE rematch_invitations SET status = 'expired', updated_at = ?
     WHERE status = 'pending' AND expires_at <= ?`,
  )
    .bind(now.toISOString(), now.toISOString())
    .run();
  const id = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO rematch_invitations (
       id, previous_match_id, sender_id, recipient_id, difficulty,
       status, created_at, updated_at, expires_at
     ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?)`,
  )
    .bind(
      id,
      previousMatchId,
      senderId,
      recipientId,
      match.difficulty,
      now.toISOString(),
      now.toISOString(),
      expires.toISOString(),
    )
    .run();
  await sendRematchPush(env, recipientId, id, previousMatchId);
  return rematchJson(env, id, senderId);
}

export async function pendingRematches(
  env: EconomyEnv,
  playerId: string,
): Promise<Record<string, unknown>> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE rematch_invitations SET status = 'expired', updated_at = ?
     WHERE status = 'pending' AND expires_at <= ?`,
  )
    .bind(now, now)
    .run();
  const rows = await env.DB.prepare(
    `SELECT * FROM rematch_invitations
     WHERE (sender_id = ? OR recipient_id = ?)
       AND created_at >= datetime('now', '-5 minutes')
     ORDER BY created_at DESC LIMIT 20`,
  )
    .bind(playerId, playerId)
    .all<RematchRow>();
  return {
    invitations: await Promise.all(rows.results.map((row) => rematchJsonFromRow(env, row, playerId))),
  };
}

export async function rematchForResponse(
  env: EconomyEnv,
  invitationId: string,
  playerId: string,
): Promise<RematchRow> {
  const row = await env.DB.prepare(
    'SELECT * FROM rematch_invitations WHERE id = ? LIMIT 1',
  )
    .bind(invitationId)
    .first<RematchRow>();
  if (!row) throw new EconomyError(404, 'Rematch invitation not found.');
  if (row.recipient_id !== playerId) {
    throw new EconomyError(403, 'Only the recipient can respond.');
  }
  if (row.status !== 'pending') {
    throw new EconomyError(409, 'Rematch invitation is no longer pending.', 'rematch_closed');
  }
  if (Date.parse(row.expires_at) <= Date.now()) {
    await markRematchStatus(env, row.id, 'expired', null);
    throw new EconomyError(409, 'Rematch invitation expired.', 'rematch_expired');
  }
  return row;
}

export async function markRematchStatus(
  env: EconomyEnv,
  invitationId: string,
  status: 'accepted' | 'declined' | 'expired' | 'insufficient_coins',
  roomId: string | null,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE rematch_invitations
     SET status = ?, room_id = ?, updated_at = ?, responded_at = ?
     WHERE id = ? AND status = 'pending'`,
  )
    .bind(status, roomId, now, now, invitationId)
    .run();
}

export async function rematchJson(
  env: EconomyEnv,
  invitationId: string,
  viewerId: string,
): Promise<Record<string, unknown>> {
  const row = await env.DB.prepare(
    'SELECT * FROM rematch_invitations WHERE id = ? LIMIT 1',
  )
    .bind(invitationId)
    .first<RematchRow>();
  if (!row) throw new EconomyError(404, 'Rematch invitation not found.');
  return rematchJsonFromRow(env, row, viewerId);
}

export async function grantTestPurchase(
  env: EconomyEnv,
  input: {
    playerId: string;
    platform: 'android' | 'ios';
    productId: string;
    transactionId: string;
    verificationData: string;
  },
): Promise<Record<string, unknown>> {
  if (input.productId === NO_ADS_PRODUCT_ID) {
    const granted = await grantNoAdsEntitlement(env, {
      playerId: input.playerId,
      platform: input.platform,
      productId: input.productId,
      transactionId: input.transactionId,
      verificationData: input.verificationData,
    });
    return { granted, amount: 0, ...(await walletSnapshot(env, input.playerId)) };
  }
  const amount = COIN_PRODUCTS[input.productId];
  if (!amount) throw new EconomyError(400, 'Unknown store product.');
  const isProduction = (env.ENVIRONMENT ?? '').toLowerCase() === 'production';
  const allowTest = (env.ALLOW_TEST_PURCHASE_GRANTS ?? '').toLowerCase() === 'true';
  if (isProduction || !allowTest) {
    throw new EconomyError(
      503,
      'Store server verification is not configured for this environment.',
      'purchase_verification_unavailable',
    );
  }
  const hash = await sha256Hex(
    `${input.platform}:${input.productId}:${input.transactionId}:${input.verificationData}`,
  );
  const existing = await env.DB.prepare(
    'SELECT player_id FROM purchase_grants WHERE transaction_id = ? OR verification_hash = ? LIMIT 1',
  )
    .bind(input.transactionId, hash)
    .first<{ player_id: string }>();
  if (existing && existing.player_id !== input.playerId) {
    throw new EconomyError(409, 'This store transaction was already used.', 'purchase_replayed');
  }
  const now = new Date().toISOString();
  if (!existing) {
    await env.DB.prepare(
      `INSERT INTO purchase_grants (
         id, player_id, platform, product_id, transaction_id,
         verification_hash, coins, status, granted_at, updated_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, 'verified', ?, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        input.playerId,
        input.platform,
        input.productId,
        input.transactionId,
        hash,
        amount,
        now,
        now,
      )
      .run();
    await grantCoinsOnce(env, {
      playerId: input.playerId,
      amount,
      reason: 'store_purchase',
      referenceType: 'purchase',
      referenceId: input.transactionId,
      idempotencyKey: `store_purchase:${input.platform}:${input.transactionId}`,
      metadata: { productId: input.productId, platform: input.platform, testGrant: true },
    });
  }
  return { granted: !existing, amount: existing ? 0 : amount, ...(await walletSnapshot(env, input.playerId)) };
}

export async function entitlementSnapshot(
  env: EconomyEnv,
  playerId: string,
): Promise<Record<string, boolean>> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM player_entitlements
     WHERE player_id = ? AND entitlement_key = 'no_ads' AND revoked_at IS NULL
     LIMIT 1`,
  )
    .bind(playerId)
    .first();
  return { noAds: !!row };
}

export async function grantNoAdsEntitlement(
  env: EconomyEnv,
  input: {
    playerId: string;
    platform: 'android' | 'ios';
    productId: string;
    transactionId: string;
    verificationData: string;
  },
): Promise<boolean> {
  if (input.productId !== NO_ADS_PRODUCT_ID) {
    throw new EconomyError(400, 'Unknown entitlement product.', 'unknown_product');
  }
  const verificationHash = await sha256Hex(
    `${input.platform}:${input.productId}:${input.transactionId}:${input.verificationData}`,
  );
  const existingSource = await env.DB.prepare(
    `SELECT player_id FROM player_entitlements
     WHERE source_transaction_id = ? OR verification_hash = ?
     LIMIT 1`,
  )
    .bind(input.transactionId, verificationHash)
    .first<{ player_id: string }>();
  if (existingSource && existingSource.player_id !== input.playerId) {
    throw new EconomyError(409, 'This store transaction was already used.', 'purchase_replayed');
  }
  const now = new Date().toISOString();
  const inserted = await env.DB.prepare(
    `INSERT INTO player_entitlements (
       id, player_id, entitlement_key, source_platform, source_product_id,
       source_transaction_id, verification_hash, granted_at, updated_at
     ) VALUES (?, ?, 'no_ads', ?, ?, ?, ?, ?, ?)
     ON CONFLICT(player_id, entitlement_key) DO UPDATE SET
       source_platform = excluded.source_platform,
       source_product_id = excluded.source_product_id,
       source_transaction_id = excluded.source_transaction_id,
       verification_hash = excluded.verification_hash,
       revoked_at = NULL,
       updated_at = excluded.updated_at`,
  )
    .bind(
      crypto.randomUUID(),
      input.playerId,
      input.platform,
      input.productId,
      input.transactionId,
      verificationHash,
      now,
      now,
    )
    .run();
  return (inserted.meta.changes ?? 0) > 0 && !existingSource;
}

export async function coinBalance(env: EconomyEnv, playerId: string): Promise<number> {
  await applyDebugUnlimitedCoins(env, playerId);
  const row = await env.DB.prepare('SELECT online_coins FROM players WHERE id = ? LIMIT 1')
    .bind(playerId)
    .first<{ online_coins: number }>();
  if (!row) throw new EconomyError(404, 'Player profile not found.');
  return Number(row.online_coins ?? 0);
}

async function applyDebugUnlimitedCoins(
  env: EconomyEnv,
  playerId: string,
): Promise<void> {
  if (!debugUnlimitedCoinsEnabled(env)) return;
  await env.DB.prepare(
    `UPDATE players
     SET online_coins = ?, updated_at = ?
     WHERE id = ? AND online_coins < ?`,
  )
    .bind(
      DEBUG_UNLIMITED_COINS_BALANCE,
      new Date().toISOString(),
      playerId,
      DEBUG_UNLIMITED_COINS_BALANCE,
    )
    .run();
}

function debugUnlimitedCoinsEnabled(env: EconomyEnv): boolean {
  return (
    env.DEBUG_UNLIMITED_COINS === 'true' &&
    (env.ENVIRONMENT ?? '').toLowerCase() !== 'production'
  );
}

async function grantCoinsOnce(
  env: EconomyEnv,
  input: {
    playerId: string;
    amount: number;
    reason:
      | 'daily_login'
      | 'daily_rewarded_ad'
      | 'career_rewarded_ad'
      | 'achievement_reward'
      | 'store_purchase';
    referenceType: string;
    referenceId: string;
    idempotencyKey: string;
    metadata: Record<string, unknown>;
  },
): Promise<boolean> {
  const current = await coinBalance(env, input.playerId);
  const now = new Date().toISOString();
  const inserted = await env.DB.prepare(
    `INSERT OR IGNORE INTO coin_ledger (
       id, player_id, amount, balance_after, reason,
       reference_type, reference_id, idempotency_key, metadata_json, created_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      input.playerId,
      input.amount,
      current + input.amount,
      input.reason,
      input.referenceType,
      input.referenceId,
      input.idempotencyKey,
      JSON.stringify(input.metadata),
      now,
    )
    .run();
  if ((inserted.meta.changes ?? 0) === 0) return false;
  await env.DB.prepare(
    'UPDATE players SET online_coins = online_coins + ?, updated_at = ? WHERE id = ?',
  )
    .bind(input.amount, now, input.playerId)
    .run();
  return true;
}

function achievementDefinition(id: string): {
  amount: number;
  tier: string;
  requirement: { kind: 'wins' | 'games' | 'rating'; value: number };
} {
  const definitions = {
    first_win: { amount: 50, tier: 'bronze', requirement: { kind: 'wins', value: 1 } },
    wins_10: { amount: 100, tier: 'silver', requirement: { kind: 'wins', value: 10 } },
    games_25: { amount: 100, tier: 'silver', requirement: { kind: 'games', value: 25 } },
    wins_50: { amount: 250, tier: 'gold', requirement: { kind: 'wins', value: 50 } },
    rating_1200: { amount: 250, tier: 'gold', requirement: { kind: 'rating', value: 1200 } },
    rating_1500: { amount: 500, tier: 'platinum', requirement: { kind: 'rating', value: 1500 } },
    wins_250: { amount: 1000, tier: 'milestone', requirement: { kind: 'wins', value: 250 } },
  } as const;
  const definition = definitions[id as keyof typeof definitions];
  if (!definition) throw new EconomyError(404, 'Unknown achievement reward.');
  return definition;
}

async function verifyAchievement(
  env: EconomyEnv,
  playerId: string,
  requirement: { kind: 'wins' | 'games' | 'rating'; value: number },
): Promise<void> {
  if (requirement.kind === 'rating') {
    const row = await env.DB.prepare(
      `SELECT MAX(rating) AS value FROM player_ratings WHERE player_id = ?`,
    )
      .bind(playerId)
      .first<{ value: number | null }>();
    if (Number(row?.value ?? 0) < requirement.value) {
      throw new EconomyError(409, 'Achievement requirement is not complete.');
    }
    return;
  }
  const row = await env.DB.prepare(
    `SELECT games_played, wins FROM players WHERE id = ?`,
  )
    .bind(playerId)
    .first<{ games_played: number; wins: number }>();
  const value = requirement.kind === 'wins' ? Number(row?.wins ?? 0) : Number(row?.games_played ?? 0);
  if (value < requirement.value) {
    throw new EconomyError(409, 'Achievement requirement is not complete.');
  }
}

async function rematchJsonFromRow(
  env: EconomyEnv,
  row: RematchRow,
  viewerId: string,
): Promise<Record<string, unknown>> {
  const [sender, recipient] = await Promise.all([
    env.DB.prepare('SELECT public_id, display_name FROM players WHERE id = ?')
      .bind(row.sender_id)
      .first<{ public_id: string; display_name: string }>(),
    env.DB.prepare('SELECT public_id, display_name FROM players WHERE id = ?')
      .bind(row.recipient_id)
      .first<{ public_id: string; display_name: string }>(),
  ]);
  return {
    id: row.id,
    previousMatchId: row.previous_match_id,
    difficulty: row.difficulty,
    status: row.status,
    roomId: row.room_id,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    isSender: row.sender_id === viewerId,
    sender: {
      publicId: sender?.public_id ?? '',
      displayName: sender?.display_name ?? 'Sudoku Player',
    },
    recipient: {
      publicId: recipient?.public_id ?? '',
      displayName: recipient?.display_name ?? 'Sudoku Player',
    },
  };
}

async function sendRematchPush(
  env: EconomyEnv,
  recipientId: string,
  invitationId: string,
  previousMatchId: string,
): Promise<void> {
  if (!env.FCM_PROJECT_ID || !env.FCM_CLIENT_EMAIL || !env.FCM_PRIVATE_KEY) return;
  // The existing worker owns the full OAuth/FCM implementation. The in-app
  // 10-second polling path remains authoritative; push is deliberately best-effort.
  console.log('rematch_push_requested', { recipientId, invitationId, previousMatchId });
}

function utcDay(value = new Date()): string {
  return value.toISOString().slice(0, 10);
}

function parseJsonObject(value: unknown): Record<string, unknown> | null {
  if (typeof value !== 'string' || !value) return null;
  try {
    const decoded = JSON.parse(value);
    return decoded && typeof decoded === 'object' && !Array.isArray(decoded)
      ? (decoded as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (item) => item.toString(16).padStart(2, '0')).join('');
}
