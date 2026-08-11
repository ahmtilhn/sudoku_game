import { coinBalance } from './economy';
import {
  adsAllowed,
  economyV3State,
  EconomyV3Error,
  insertCoinEvent,
  type EconomyV3Env,
  utcDay,
} from './economy_v3_common';
import {
  RECOVERY_COOLDOWN_MS,
  RECOVERY_DAILY_COIN_CAP,
  RECOVERY_DAILY_POPUP_CAP,
  recoveryAmount,
} from './economy_v3_policy';
import { markClaimed, preparedClaim } from './economy_v3_rewards';

export async function prepareDuelRecovery(
  env: EconomyV3Env,
  playerId: string,
  matchId: string,
): Promise<Record<string, unknown>> {
  if (!(await adsAllowed(env, playerId))) {
    return { eligible: false, code: 'ads_disabled_entitlement' };
  }

  const existing = await env.DB.prepare(
    `SELECT trigger_kind, offered_amount, status, verification_token
     FROM economy_v3_recovery_matches
     WHERE player_id = ? AND match_id = ?`,
  )
    .bind(playerId, matchId)
    .first<{
      trigger_kind: string;
      offered_amount: number;
      status: string;
      verification_token: string | null;
    }>();
  if (existing) {
    return {
      eligible: existing.status === 'prepared',
      trigger: existing.trigger_kind,
      amount: existing.offered_amount,
      token: existing.status === 'prepared' ? existing.verification_token : null,
      status: existing.status,
      ...(await economyV3State(env, playerId)),
    };
  }

  const loss = await env.DB.prepare(
    `SELECT s.loser_id, e.player_a_id, e.player_b_id,
            e.player_a_amount, e.player_b_amount, e.status AS escrow_status
     FROM match_coin_settlements s
     JOIN match_coin_escrow e ON e.match_id = s.match_id
     WHERE s.match_id = ? AND s.loser_id = ?
     LIMIT 1`,
  )
    .bind(matchId, playerId)
    .first<{
      loser_id: string;
      player_a_id: string;
      player_b_id: string;
      player_a_amount: number;
      player_b_amount: number;
      escrow_status: string;
    }>();
  if (!loss || loss.escrow_status !== 'paid') {
    return { eligible: false, code: 'not_verified_loss' };
  }

  const entryFee =
    loss.player_a_id === playerId
      ? Number(loss.player_a_amount)
      : Number(loss.player_b_amount);
  const balance = await coinBalance(env, playerId);
  const beforeLoss = balance + entryFee;
  const lossRatio = beforeLoss > 0 ? entryFee / beforeLoss : 1;
  let trigger: 'large_loss' | 'balance_shock' | 'broke' | null = null;
  if (balance <= 0) trigger = 'broke';
  else if (entryFee >= 400) trigger = 'large_loss';
  else if (lossRatio >= 0.30) trigger = 'balance_shock';
  if (!trigger) {
    return { eligible: false, code: 'loss_not_significant' };
  }

  const day = utcDay();
  const daily = await env.DB.prepare(
    `SELECT coins_earned, popup_count, last_popup_at
     FROM economy_v3_recovery_daily WHERE player_id = ? AND day_key = ?`,
  )
    .bind(playerId, day)
    .first<{ coins_earned: number; popup_count: number; last_popup_at: string | null }>();
  const coinsEarned = Number(daily?.coins_earned ?? 0);
  const popupCount = Number(daily?.popup_count ?? 0);
  if (popupCount >= RECOVERY_DAILY_POPUP_CAP) {
    return { eligible: false, code: 'recovery_popup_cap' };
  }
  if (coinsEarned >= RECOVERY_DAILY_COIN_CAP) {
    return { eligible: false, code: 'recovery_coin_cap' };
  }
  if (trigger !== 'broke' && daily?.last_popup_at) {
    const sinceLastPopup = Date.now() - Date.parse(daily.last_popup_at);
    if (
      Number.isFinite(sinceLastPopup) &&
      sinceLastPopup >= 0 &&
      sinceLastPopup < RECOVERY_COOLDOWN_MS
    ) {
      return { eligible: false, code: 'recovery_cooldown' };
    }
  }

  const rawAmount = recoveryAmount(entryFee, trigger === 'broke');
  const amount = Math.min(rawAmount, RECOVERY_DAILY_COIN_CAP - coinsEarned);
  if (amount < 25) {
    return { eligible: false, code: 'recovery_coin_cap' };
  }

  const token = crypto.randomUUID();
  const now = new Date();
  const expires = new Date(now.getTime() + 15 * 60 * 1000);
  const rewardKey = `v3_recovery:${matchId}`;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO reward_claims (
         id, player_id, reward_type, reward_key, amount, status,
         verification_token, prepared_at, expires_at
       ) VALUES (?, ?, 'career_rewarded_ad', ?, ?, 'prepared', ?, ?, ?)`,
    ).bind(
      crypto.randomUUID(),
      playerId,
      rewardKey,
      amount,
      token,
      now.toISOString(),
      expires.toISOString(),
    ),
    env.DB.prepare(
      `INSERT INTO economy_v3_recovery_matches (
         player_id, match_id, trigger_kind, offered_amount, status,
         verification_token, created_at
       ) VALUES (?, ?, ?, ?, 'prepared', ?, ?)`,
    ).bind(playerId, matchId, trigger, amount, token, now.toISOString()),
    env.DB.prepare(
      `INSERT INTO economy_v3_recovery_daily (
         player_id, day_key, coins_earned, popup_count, last_popup_at, updated_at
       ) VALUES (?, ?, 0, 1, ?, ?)
       ON CONFLICT(player_id, day_key) DO UPDATE SET
         popup_count = economy_v3_recovery_daily.popup_count + 1,
         last_popup_at = excluded.last_popup_at,
         updated_at = excluded.updated_at`,
    ).bind(playerId, day, now.toISOString(), now.toISOString()),
  ]);

  return {
    eligible: true,
    trigger,
    amount,
    token,
    matchId,
    expiresAt: expires.toISOString(),
    entryFee,
    lossRatio,
    ...(await economyV3State(env, playerId)),
  };
}

export async function confirmDuelRecovery(
  env: EconomyV3Env,
  playerId: string,
  token: string,
): Promise<Record<string, unknown>> {
  const claim = await preparedClaim(env, playerId, token, 'v3_recovery:');
  const matchId = String(claim.reward_key).substring('v3_recovery:'.length);
  const recovery = await env.DB.prepare(
    `SELECT status, offered_amount FROM economy_v3_recovery_matches
     WHERE player_id = ? AND match_id = ? AND verification_token = ?`,
  )
    .bind(playerId, matchId, token)
    .first<{ status: string; offered_amount: number }>();
  if (!recovery) {
    throw new EconomyV3Error(404, 'Recovery offer not found.', 'recovery_not_found');
  }
  if (recovery.status === 'claimed' || claim.status === 'claimed') {
    return { granted: false, amount: 0, ...(await economyV3State(env, playerId)) };
  }

  const day = utcDay();
  const daily = await env.DB.prepare(
    `SELECT coins_earned FROM economy_v3_recovery_daily
     WHERE player_id = ? AND day_key = ?`,
  )
    .bind(playerId, day)
    .first<{ coins_earned: number }>();
  const remaining = Math.max(
    0,
    RECOVERY_DAILY_COIN_CAP - Number(daily?.coins_earned ?? 0),
  );
  const amount = Math.min(Number(recovery.offered_amount), remaining);
  if (amount <= 0) {
    throw new EconomyV3Error(409, 'Recovery daily limit reached.', 'recovery_coin_cap');
  }

  const inserted = await insertCoinEvent(env, {
    playerId,
    source: 'duel_recovery',
    referenceId: matchId,
    amount,
    ledgerReason: 'career_rewarded_ad',
    metadata: { matchId, recovery: true, dayKey: day },
  });
  await markClaimed(env, claim.id);
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE economy_v3_recovery_matches
       SET status = 'claimed', claimed_at = ?
       WHERE player_id = ? AND match_id = ?`,
    ).bind(now, playerId, matchId),
    env.DB.prepare(
      `UPDATE economy_v3_recovery_daily
       SET coins_earned = coins_earned + ?, updated_at = ?
       WHERE player_id = ? AND day_key = ?`,
    ).bind(inserted ? amount : 0, now, playerId, day),
  ]);
  return {
    granted: inserted,
    amount: inserted ? amount : 0,
    matchId,
    ...(await economyV3State(env, playerId)),
  };
}

export async function dismissDuelRecovery(
  env: EconomyV3Env,
  playerId: string,
  matchId: string,
): Promise<Record<string, unknown>> {
  await env.DB.prepare(
    `UPDATE economy_v3_recovery_matches
     SET status = 'dismissed'
     WHERE player_id = ? AND match_id = ? AND status = 'prepared'`,
  )
    .bind(playerId, matchId)
    .run();
  return { dismissed: true };
}
