import { ensureStarterGrant, walletSnapshot, type EconomyEnv } from './economy';
import {
  CAREER_DAILY_COIN_CAP,
  CAREER_REWARDS,
  DAILY_REWARD_CALENDAR,
  HINT_COIN_COST,
  HINT_REFILL_SIZE,
  RECOVERY_DAILY_COIN_CAP,
  RECOVERY_DAILY_POPUP_CAP,
} from './economy_v3_policy';
import { ensureEconomyV3Schema } from './economy_v3_schema';

export type EconomyV3Env = EconomyEnv & {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
  ADMOB_REWARDED_AD_UNITS?: string;
  ALLOWED_ORIGIN?: string;
};

export type LegacyFetch = (request: Request) => Promise<Response>;

export class EconomyV3Error extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

export async function prepareEconomyV3Request(
  request: Request,
  env: EconomyV3Env,
  legacyFetch: LegacyFetch,
): Promise<string> {
  await ensureEconomyV3Schema(env);
  const profileRequest = new Request(new URL('/v1/me', request.url), {
    method: 'POST',
    headers: request.headers,
    body: '{}',
  });
  const response = await legacyFetch(profileRequest);
  if (!response.ok) {
    let message = 'Unable to authenticate the player.';
    let code = 'profile_auth_failed';
    try {
      const body = (await response.clone().json()) as Record<string, unknown>;
      message = String(body.error ?? message);
      code = String(body.code ?? code);
    } catch {
      // Keep the safe default.
    }
    throw new EconomyV3Error(response.status, message, code);
  }
  const body = (await response.json()) as Record<string, unknown>;
  const publicId = String(body.publicId ?? '').trim();
  if (!publicId) {
    throw new EconomyV3Error(500, 'Player profile is missing its public ID.', 'profile_public_id_missing');
  }
  const player = await env.DB.prepare('SELECT id FROM players WHERE public_id = ? LIMIT 1')
    .bind(publicId)
    .first<{ id: string }>();
  if (!player) {
    throw new EconomyV3Error(500, 'Unable to load player profile.', 'profile_missing');
  }
  await ensureStarterGrant(env, player.id);
  return player.id;
}

export async function economyV3State(
  env: EconomyV3Env,
  playerId: string,
): Promise<Record<string, unknown>> {
  const day = utcDay();
  const [daily, inventory, careerDaily, recoveryDaily, wallet] = await Promise.all([
    dailyStateRow(env, playerId),
    inventoryRow(env, playerId),
    env.DB.prepare(
      'SELECT coins_earned FROM economy_v3_career_daily WHERE player_id = ? AND day_key = ?',
    )
      .bind(playerId, day)
      .first<{ coins_earned: number }>(),
    env.DB.prepare(
      `SELECT coins_earned, popup_count, last_popup_at
       FROM economy_v3_recovery_daily WHERE player_id = ? AND day_key = ?`,
    )
      .bind(playerId, day)
      .first<{ coins_earned: number; popup_count: number; last_popup_at: string | null }>(),
    walletSnapshot(env, playerId),
  ]);
  const nextSequence = daily.claims_total + 1;
  const cycleDay = ((nextSequence - 1) % DAILY_REWARD_CALENDAR.length) + 1;
  const nextReset = new Date(`${day}T00:00:00.000Z`);
  nextReset.setUTCDate(nextReset.getUTCDate() + 1);
  const careerEarned = Number(careerDaily?.coins_earned ?? 0);
  return {
    version: 3,
    wallet,
    balance: Number(wallet.balance ?? 0),
    daily: {
      cycleDay,
      claimsTotal: daily.claims_total,
      available: daily.last_claim_day !== day,
      nextReward: DAILY_REWARD_CALENDAR[cycleDay - 1],
      lastClaimDay: daily.last_claim_day,
      lastClaimSequence: daily.last_claim_sequence,
      lastClaimAmount: daily.last_claim_amount,
      canDoubleLastCoinReward:
        daily.last_claim_day === day &&
        daily.last_claim_amount > 0 &&
        daily.doubled_sequence !== daily.last_claim_sequence,
      calendar: DAILY_REWARD_CALENDAR,
      nextResetAt: nextReset.toISOString(),
    },
    inventory: {
      hintRefills: inventory.hint_refills,
      hintRefillSize: HINT_REFILL_SIZE,
      hintCoinCost: HINT_COIN_COST,
    },
    career: {
      dailyCap: CAREER_DAILY_COIN_CAP,
      earnedToday: careerEarned,
      remainingToday: Math.max(0, CAREER_DAILY_COIN_CAP - careerEarned),
      rewards: CAREER_REWARDS,
    },
    recovery: {
      dailyCoinCap: RECOVERY_DAILY_COIN_CAP,
      dailyPopupCap: RECOVERY_DAILY_POPUP_CAP,
      earnedToday: Number(recoveryDaily?.coins_earned ?? 0),
      popupCountToday: Number(recoveryDaily?.popup_count ?? 0),
      lastPopupAt: recoveryDaily?.last_popup_at ?? null,
    },
  };
}

export async function dailyStateRow(
  env: EconomyV3Env,
  playerId: string,
): Promise<{
  claims_total: number;
  last_claim_day: string | null;
  last_claim_sequence: number;
  last_claim_amount: number;
  doubled_sequence: number;
}> {
  return (
    (await env.DB.prepare(
      `SELECT claims_total, last_claim_day, last_claim_sequence,
              last_claim_amount, doubled_sequence
       FROM economy_v3_daily_state WHERE player_id = ?`,
    )
      .bind(playerId)
      .first<{
        claims_total: number;
        last_claim_day: string | null;
        last_claim_sequence: number;
        last_claim_amount: number;
        doubled_sequence: number;
      }>()) ?? {
      claims_total: 0,
      last_claim_day: null,
      last_claim_sequence: 0,
      last_claim_amount: 0,
      doubled_sequence: 0,
    }
  );
}

export async function inventoryRow(
  env: EconomyV3Env,
  playerId: string,
): Promise<{ hint_refills: number }> {
  return (
    (await env.DB.prepare(
      'SELECT hint_refills FROM economy_v3_inventory WHERE player_id = ?',
    )
      .bind(playerId)
      .first<{ hint_refills: number }>()) ?? { hint_refills: 0 }
  );
}

export async function insertCoinEvent(
  env: EconomyV3Env,
  input: {
    playerId: string;
    source: string;
    referenceId: string;
    amount: number;
    ledgerReason:
      | 'daily_login'
      | 'daily_rewarded_ad'
      | 'career_rewarded_ad'
      | 'achievement_reward'
      | 'career_continue';
    metadata?: Record<string, unknown>;
  },
): Promise<boolean> {
  try {
    const result = await env.DB.prepare(
      `INSERT OR IGNORE INTO economy_v3_coin_events (
         id, player_id, source, reference_id, amount, ledger_reason,
         metadata_json, created_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        input.playerId,
        input.source,
        input.referenceId,
        input.amount,
        input.ledgerReason,
        JSON.stringify(input.metadata ?? {}),
        new Date().toISOString(),
      )
      .run();
    return (result.meta.changes ?? 0) > 0;
  } catch (error) {
    if (String(error).includes('insufficient_coins')) {
      throw new EconomyV3Error(409, 'Not enough Coins.', 'insufficient_coins');
    }
    throw error;
  }
}

export async function insertInventoryEvent(
  env: EconomyV3Env,
  input: {
    playerId: string;
    source: string;
    referenceId: string;
    refillDelta: number;
  },
): Promise<boolean> {
  const result = await env.DB.prepare(
    `INSERT OR IGNORE INTO economy_v3_inventory_events (
       id, player_id, source, reference_id, refill_delta, created_at
     ) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      input.playerId,
      input.source,
      input.referenceId,
      input.refillDelta,
      new Date().toISOString(),
    )
    .run();
  return (result.meta.changes ?? 0) > 0;
}

export async function adsAllowed(env: EconomyV3Env, playerId: string): Promise<boolean> {
  const entitlement = await env.DB.prepare(
    `SELECT 1 FROM player_entitlements
     WHERE player_id = ? AND entitlement_key = 'no_ads' AND revoked_at IS NULL
     LIMIT 1`,
  )
    .bind(playerId)
    .first();
  return !entitlement;
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
  } catch {
    // handled below
  }
  throw new EconomyV3Error(400, 'Invalid JSON body.', 'invalid_json');
}

export function requiredString(value: unknown, field: string, max = 256): string {
  const text = String(value ?? '').trim();
  if (!text || text.length > max) {
    throw new EconomyV3Error(400, `Invalid ${field}.`, `invalid_${field}`);
  }
  return text;
}

export function positiveInt(value: unknown, field: string): number {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 1 || number > 1_000_000) {
    throw new EconomyV3Error(400, `Invalid ${field}.`, `invalid_${field}`);
  }
  return number;
}

export function utcDay(date = new Date()): string {
  return date.toISOString().slice(0, 10);
}

export function json(env: EconomyV3Env, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
      'access-control-allow-headers': 'authorization, content-type, x-firebase-appcheck',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
    },
  });
}

export function errorResponse(env: EconomyV3Env, error: unknown): Response {
  if (error instanceof EconomyV3Error) {
    return json(env, error.status, { error: error.message, code: error.code });
  }
  const candidate = error as { status?: unknown; code?: unknown; message?: unknown };
  const status = Number(candidate?.status);
  if (Number.isInteger(status) && status >= 400 && status < 600) {
    return json(env, status, {
      error: String(candidate.message ?? 'Economy request failed.'),
      code: String(candidate.code ?? 'economy_error'),
    });
  }
  console.error('economy_v3_failed', error);
  return json(env, 500, { error: 'Economy V3 request failed.', code: 'economy_v3_failed' });
}
