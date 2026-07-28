import { createRemoteJWKSet, importSPKI, jwtVerify } from 'jose';

import { verifyAppCheckRequest } from './app_check';

const ADMOB_KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json';
const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);
const KEY_CACHE_MS = 24 * 60 * 60 * 1000;
const MAX_CALLBACK_AGE_MS = 24 * 60 * 60 * 1000;
const FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000;

type AdMobKey = {
  keyId: number;
  pem: string;
};

type CachedKeys = {
  expiresAt: number;
  values: Map<number, string>;
};

let cachedKeys: CachedKeys | null = null;

export type AdMobSsvEnv = {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
  ENVIRONMENT?: string;
  ADMOB_REWARDED_AD_UNITS?: string;
};

export class AdMobSsvError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

export function isAdMobSsvPath(pathname: string): boolean {
  return pathname === '/v1/rewards/admob/ssv';
}

export async function handleAdMobSsv(
  request: Request,
  env: AdMobSsvEnv,
): Promise<Response> {
  if (request.method !== 'GET') {
    return json(405, { error: 'Method not allowed.', code: 'method_not_allowed' });
  }

  try {
    const callback = parseCallback(request.url);
    await verifyCallbackSignature(callback);
    validateCallbackPolicy(callback, env);
    await markRewardVerified(env, callback);
    return json(200, { ok: true });
  } catch (error) {
    if (error instanceof AdMobSsvError) {
      console.warn('AdMob SSV rejected', error.code, error.message);
      return json(error.status, { error: error.message, code: error.code });
    }
    console.error('AdMob SSV failed', error);
    return json(500, { error: 'AdMob SSV verification failed.', code: 'ssv_failed' });
  }
}

export async function assertProductionRewardConfirmedBySsv(
  request: Request,
  env: AdMobSsvEnv,
): Promise<void> {
  if ((env.ENVIRONMENT ?? '').toLowerCase() !== 'production') return;
  if (request.method !== 'POST') return;

  await verifyAppCheckRequest(request, env);
  const playerId = await authenticatedPlayerId(request, env);
  const token = await rewardTokenFromRequest(request);
  const claim = await env.DB.prepare(
    `SELECT status, expires_at, ssv_verified_at
     FROM reward_claims
     WHERE player_id = ? AND verification_token = ? LIMIT 1`,
  )
    .bind(playerId, token)
    .first<{
      status: string;
      expires_at: string | null;
      ssv_verified_at: string | null;
    }>();
  if (!claim) {
    throw new AdMobSsvError(404, 'Reward preparation not found.', 'reward_not_found');
  }
  if (claim.status === 'claimed') return;
  if (claim.status !== 'prepared') {
    throw new AdMobSsvError(409, 'Reward is no longer available.', 'reward_unavailable');
  }
  if (claim.expires_at && Date.parse(claim.expires_at) <= Date.now()) {
    throw new AdMobSsvError(409, 'Reward confirmation expired.', 'reward_expired');
  }
  if (!claim.ssv_verified_at) {
    throw new AdMobSsvError(
      409,
      'The rewarded ad is still waiting for server verification.',
      'reward_waiting_for_ssv',
    );
  }
}

type ParsedCallback = {
  signedContent: Uint8Array;
  signature: Uint8Array;
  keyId: number;
  adUnit: string;
  customData: string;
  rewardAmount: number;
  rewardItem: string;
  timestamp: number;
  transactionId: string;
};

function parseCallback(rawUrl: string): ParsedCallback {
  const question = rawUrl.indexOf('?');
  if (question < 0) {
    throw new AdMobSsvError(400, 'Missing SSV query string.', 'ssv_query_missing');
  }
  const rawQuery = rawUrl.slice(question + 1);
  const signatureMarker = '&signature=';
  const markerIndex = rawQuery.indexOf(signatureMarker);
  if (markerIndex <= 0) {
    throw new AdMobSsvError(400, 'Missing SSV signature.', 'ssv_signature_missing');
  }
  const signedContent = new TextEncoder().encode(rawQuery.slice(0, markerIndex));
  const params = new URLSearchParams(rawQuery);
  const signatureText = requiredParam(params, 'signature', 8, 2048);
  const keyId = Number(requiredParam(params, 'key_id', 1, 32));
  const rewardAmount = Number(requiredParam(params, 'reward_amount', 1, 20));
  const timestamp = Number(requiredParam(params, 'timestamp', 1, 32));
  if (!Number.isInteger(keyId) || keyId < 0) {
    throw new AdMobSsvError(400, 'Invalid SSV key ID.', 'ssv_key_invalid');
  }
  if (!Number.isFinite(rewardAmount) || rewardAmount < 0) {
    throw new AdMobSsvError(400, 'Invalid SSV reward amount.', 'ssv_reward_invalid');
  }
  if (!Number.isFinite(timestamp) || timestamp <= 0) {
    throw new AdMobSsvError(400, 'Invalid SSV timestamp.', 'ssv_timestamp_invalid');
  }

  return {
    signedContent,
    signature: base64UrlDecode(signatureText),
    keyId,
    adUnit: requiredParam(params, 'ad_unit', 1, 128),
    customData: requiredParam(params, 'custom_data', 8, 256),
    rewardAmount,
    rewardItem: requiredParam(params, 'reward_item', 1, 64),
    timestamp,
    transactionId: requiredParam(params, 'transaction_id', 8, 256),
  };
}

async function verifyCallbackSignature(callback: ParsedCallback): Promise<void> {
  const keys = await admobKeys();
  const pem = keys.get(callback.keyId);
  if (!pem) {
    cachedKeys = null;
    const refreshed = await admobKeys();
    const refreshedPem = refreshed.get(callback.keyId);
    if (!refreshedPem) {
      throw new AdMobSsvError(400, 'Unknown AdMob SSV key.', 'ssv_key_unknown');
    }
    await verifyWithPem(refreshedPem, callback);
    return;
  }
  await verifyWithPem(pem, callback);
}

async function verifyWithPem(
  pem: string,
  callback: ParsedCallback,
): Promise<void> {
  const key = await importSPKI(pem, 'ES256');
  const rawSignature = derEcdsaToRaw(callback.signature, 32);
  const verified = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    key as CryptoKey,
    rawSignature,
    callback.signedContent,
  );
  if (!verified) {
    throw new AdMobSsvError(400, 'Invalid AdMob SSV signature.', 'ssv_signature_invalid');
  }
}

function validateCallbackPolicy(
  callback: ParsedCallback,
  env: AdMobSsvEnv,
): void {
  const now = Date.now();
  if (callback.timestamp < now - MAX_CALLBACK_AGE_MS) {
    throw new AdMobSsvError(409, 'The AdMob SSV callback is too old.', 'ssv_too_old');
  }
  if (callback.timestamp > now + FUTURE_CLOCK_SKEW_MS) {
    throw new AdMobSsvError(
      409,
      'The AdMob SSV callback timestamp is in the future.',
      'ssv_in_future',
    );
  }
  const allowedUnits = (env.ADMOB_REWARDED_AD_UNITS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  if (
    (env.ENVIRONMENT ?? '').toLowerCase() === 'production' &&
    allowedUnits.length === 0
  ) {
    throw new AdMobSsvError(
      503,
      'Production rewarded ad units are not configured.',
      'ssv_ad_units_missing',
    );
  }
  if (allowedUnits.length > 0 && !allowedUnits.includes(callback.adUnit)) {
    throw new AdMobSsvError(403, 'Unexpected rewarded ad unit.', 'ssv_ad_unit_rejected');
  }
}

async function markRewardVerified(
  env: AdMobSsvEnv,
  callback: ParsedCallback,
): Promise<void> {
  const claim = await env.DB.prepare(
    `SELECT id, status, expires_at, ssv_transaction_id
     FROM reward_claims
     WHERE verification_token = ? LIMIT 1`,
  )
    .bind(callback.customData)
    .first<{
      id: string;
      status: string;
      expires_at: string | null;
      ssv_transaction_id: string | null;
    }>();
  if (!claim) {
    throw new AdMobSsvError(404, 'Reward token was not found.', 'reward_not_found');
  }
  if (claim.status === 'claimed' && claim.ssv_transaction_id === callback.transactionId) {
    return;
  }
  if (claim.status !== 'prepared') {
    throw new AdMobSsvError(409, 'Reward is no longer available.', 'reward_unavailable');
  }
  if (claim.expires_at && Date.parse(claim.expires_at) <= Date.now()) {
    throw new AdMobSsvError(409, 'Reward preparation expired.', 'reward_expired');
  }

  const duplicate = await env.DB.prepare(
    `SELECT id, verification_token FROM reward_claims
     WHERE ssv_transaction_id = ? LIMIT 1`,
  )
    .bind(callback.transactionId)
    .first<{ id: string; verification_token: string | null }>();
  if (duplicate && duplicate.id !== claim.id) {
    throw new AdMobSsvError(
      409,
      'This rewarded-ad transaction was already used.',
      'ssv_replayed',
    );
  }

  const result = await env.DB.prepare(
    `UPDATE reward_claims
     SET ssv_transaction_id = ?, ssv_verified_at = ?, ssv_ad_unit = ?,
         ssv_reward_amount = ?, ssv_reward_item = ?
     WHERE id = ? AND status = 'prepared' AND ssv_verified_at IS NULL`,
  )
    .bind(
      callback.transactionId,
      new Date().toISOString(),
      callback.adUnit,
      Math.trunc(callback.rewardAmount),
      callback.rewardItem,
      claim.id,
    )
    .run();
  if ((result.meta.changes ?? 0) === 0) {
    const updated = await env.DB.prepare(
      'SELECT ssv_transaction_id FROM reward_claims WHERE id = ?',
    )
      .bind(claim.id)
      .first<{ ssv_transaction_id: string | null }>();
    if (updated?.ssv_transaction_id !== callback.transactionId) {
      throw new AdMobSsvError(409, 'Reward verification conflicted.', 'ssv_conflict');
    }
  }
}

async function authenticatedPlayerId(
  request: Request,
  env: AdMobSsvEnv,
): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) {
    throw new AdMobSsvError(401, 'Missing bearer token.', 'missing_token');
  }
  const token = header.slice(7).trim();
  if (!token) throw new AdMobSsvError(401, 'Missing bearer token.', 'missing_token');
  const issuer = `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`;
  let uid: string | undefined;
  try {
    const result = await jwtVerify(token, FIREBASE_JWKS, {
      algorithms: ['RS256'],
      issuer,
      audience: env.FIREBASE_PROJECT_ID,
    });
    uid = result.payload.sub;
  } catch {
    throw new AdMobSsvError(401, 'Invalid or expired player token.', 'invalid_token');
  }
  if (!uid) throw new AdMobSsvError(401, 'Invalid player token.', 'invalid_token');
  const player = await env.DB.prepare(
    'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
  )
    .bind(uid)
    .first<{ id: string }>();
  if (!player) throw new AdMobSsvError(404, 'Player profile was not found.', 'player_not_found');
  return player.id;
}

async function rewardTokenFromRequest(request: Request): Promise<string> {
  let body: Record<string, unknown>;
  try {
    const value = await request.clone().json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    body = value as Record<string, unknown>;
  } catch {
    throw new AdMobSsvError(400, 'Invalid reward request.', 'invalid_json');
  }
  const token = body.token;
  if (typeof token !== 'string' || token.trim().length < 8 || token.length > 256) {
    throw new AdMobSsvError(400, 'Invalid reward token.', 'reward_token_invalid');
  }
  return token.trim();
}

async function admobKeys(): Promise<Map<number, string>> {
  if (cachedKeys && cachedKeys.expiresAt > Date.now()) return cachedKeys.values;
  const response = await fetch(ADMOB_KEYS_URL, {
    headers: { accept: 'application/json' },
  });
  if (!response.ok) {
    throw new AdMobSsvError(503, 'AdMob verification keys are unavailable.', 'ssv_keys_unavailable');
  }
  const body = (await response.json()) as { keys?: AdMobKey[] };
  const values = new Map<number, string>();
  for (const item of body.keys ?? []) {
    if (
      Number.isInteger(item.keyId) &&
      typeof item.pem === 'string' &&
      item.pem.includes('BEGIN PUBLIC KEY')
    ) {
      values.set(item.keyId, item.pem);
    }
  }
  if (values.size === 0) {
    throw new AdMobSsvError(503, 'AdMob returned no verification keys.', 'ssv_keys_empty');
  }
  cachedKeys = { expiresAt: Date.now() + KEY_CACHE_MS, values };
  return values;
}

function derEcdsaToRaw(der: Uint8Array, size: number): Uint8Array {
  let offset = 0;
  if (der[offset++] !== 0x30) {
    throw new AdMobSsvError(400, 'Invalid ECDSA signature.', 'ssv_signature_invalid');
  }
  const sequenceLength = readDerLength(der, offset);
  offset = sequenceLength.next;
  const sequenceEnd = offset + sequenceLength.length;
  if (sequenceEnd !== der.length || der[offset++] !== 0x02) {
    throw new AdMobSsvError(400, 'Invalid ECDSA signature.', 'ssv_signature_invalid');
  }
  const rLength = readDerLength(der, offset);
  offset = rLength.next;
  const r = der.slice(offset, offset + rLength.length);
  offset += rLength.length;
  if (der[offset++] !== 0x02) {
    throw new AdMobSsvError(400, 'Invalid ECDSA signature.', 'ssv_signature_invalid');
  }
  const sLength = readDerLength(der, offset);
  offset = sLength.next;
  const s = der.slice(offset, offset + sLength.length);
  offset += sLength.length;
  if (offset !== sequenceEnd) {
    throw new AdMobSsvError(400, 'Invalid ECDSA signature.', 'ssv_signature_invalid');
  }
  const raw = new Uint8Array(size * 2);
  raw.set(normalizeInteger(r, size), 0);
  raw.set(normalizeInteger(s, size), size);
  return raw;
}

function readDerLength(
  bytes: Uint8Array,
  offset: number,
): { length: number; next: number } {
  const first = bytes[offset];
  if (first == null) {
    throw new AdMobSsvError(400, 'Invalid DER length.', 'ssv_signature_invalid');
  }
  if ((first & 0x80) === 0) return { length: first, next: offset + 1 };
  const count = first & 0x7f;
  if (count < 1 || count > 2 || offset + count >= bytes.length) {
    throw new AdMobSsvError(400, 'Invalid DER length.', 'ssv_signature_invalid');
  }
  let length = 0;
  for (let index = 0; index < count; index++) {
    length = (length << 8) | bytes[offset + 1 + index];
  }
  return { length, next: offset + 1 + count };
}

function normalizeInteger(value: Uint8Array, size: number): Uint8Array {
  let start = 0;
  while (start < value.length - 1 && value[start] === 0) start++;
  const clean = value.slice(start);
  if (clean.length > size) {
    throw new AdMobSsvError(400, 'Invalid ECDSA integer.', 'ssv_signature_invalid');
  }
  const result = new Uint8Array(size);
  result.set(clean, size - clean.length);
  return result;
}

function base64UrlDecode(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  let binary: string;
  try {
    binary = atob(padded);
  } catch {
    throw new AdMobSsvError(400, 'Invalid SSV signature encoding.', 'ssv_signature_invalid');
  }
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function requiredParam(
  params: URLSearchParams,
  name: string,
  min: number,
  max: number,
): string {
  const value = params.get(name)?.trim() ?? '';
  if (value.length < min || value.length > max) {
    throw new AdMobSsvError(400, `Invalid ${name} parameter.`, 'ssv_parameter_invalid');
  }
  return value;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}
