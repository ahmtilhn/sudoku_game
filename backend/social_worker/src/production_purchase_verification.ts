import {
  SignJWT,
  createRemoteJWKSet,
  decodeJwt,
  importPKCS8,
  jwtVerify,
} from 'jose';

import { verifyAppCheckRequest } from './app_check';

const COIN_PRODUCTS: Readonly<Record<string, number>> = Object.freeze({
  coins_100: 100,
  coins_500: 500,
  coins_1000: 1000,
  coins_5000: 5000,
  coins_10000: 10000,
  coins_50000: 50000,
  coins_100000: 100000,
});
const NO_ADS_PRODUCT_ID = 'no_ads';
const IOS_NO_ADS_PRODUCT_ID = 'sudoku_duel_no_ads';

function isNoAdsProductId(productId: string): boolean {
  return productId === NO_ADS_PRODUCT_ID || productId === IOS_NO_ADS_PRODUCT_ID;
}

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

export type ProductionPurchaseEnv = {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
  ENVIRONMENT?: string;
  GOOGLE_PLAY_CLIENT_EMAIL?: string;
  GOOGLE_PLAY_PRIVATE_KEY?: string;
  GOOGLE_PLAY_PACKAGE_NAME?: string;
  APPLE_IAP_ISSUER_ID?: string;
  APPLE_IAP_KEY_ID?: string;
  APPLE_IAP_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID?: string;
};

type PurchaseInput = {
  productId: string;
  transactionId: string;
  verificationData: string;
};

type VerifiedPurchase = {
  platform: 'android' | 'ios';
  productId: string;
  transactionId: string;
  verificationData: string;
  purchasedAt: string | null;
  storeEnvironment: string | null;
  storeOrderId: string | null;
  verificationSource: string;
  productType: 'consumable' | 'non_consumable';
  consume?: () => Promise<boolean>;
};

type PlayerRow = {
  id: string;
  firebase_uid: string;
};

type GoogleAccessToken = {
  value: string;
  expiresAt: number;
};

let cachedGoogleAccessToken: GoogleAccessToken | null = null;

export class ProductionVerificationError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

export function isProductionPurchasePath(pathname: string): boolean {
  return (
    pathname === '/v1/purchases/google/verify' ||
    pathname === '/v1/purchases/apple/verify'
  );
}

export async function verifyAndGrantProductionPurchase(
  request: Request,
  env: ProductionPurchaseEnv,
): Promise<{ playerId: string; granted: boolean; consumed: boolean | null }> {
  if ((env.ENVIRONMENT ?? '').toLowerCase() !== 'production') {
    throw new ProductionVerificationError(
      400,
      'Production purchase verification was called outside production.',
      'invalid_environment',
    );
  }
  if (request.method !== 'POST') {
    throw new ProductionVerificationError(405, 'Method not allowed.', 'method_not_allowed');
  }

  await verifyAppCheckRequest(request, env);
  const player = await authenticatePlayer(request, env);
  const input = await readPurchaseInput(request);
  const pathname = new URL(request.url).pathname;
  const verified = pathname.includes('/google/')
    ? await verifyGooglePlayPurchase(env, input)
    : await verifyAppStorePurchase(env, input);

  const granted = await grantVerifiedPurchase(env, player.id, verified);
  let consumed: boolean | null = null;
  if (verified.consume) {
    try {
      consumed = await verified.consume();
      if (consumed) {
        await env.DB.prepare(
          `UPDATE purchase_grants SET consumed_at = COALESCE(consumed_at, ?), updated_at = ?
           WHERE platform = 'android' AND transaction_id = ?`,
        )
          .bind(new Date().toISOString(), new Date().toISOString(), verified.transactionId)
          .run();
      }
    } catch (error) {
      consumed = false;
      console.error('Google Play purchase consumption failed', error);
    }
  }

  return { playerId: player.id, granted, consumed };
}

async function authenticatePlayer(
  request: Request,
  env: ProductionPurchaseEnv,
): Promise<PlayerRow> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) {
    throw new ProductionVerificationError(401, 'Missing bearer token.', 'missing_token');
  }
  const token = header.slice(7).trim();
  if (!token) {
    throw new ProductionVerificationError(401, 'Missing bearer token.', 'missing_token');
  }

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
    throw new ProductionVerificationError(
      401,
      'Invalid or expired Firebase ID token.',
      'invalid_token',
    );
  }
  if (!uid) {
    throw new ProductionVerificationError(401, 'Invalid player token.', 'invalid_token');
  }

  const player = await env.DB.prepare(
    'SELECT id, firebase_uid FROM players WHERE firebase_uid = ? LIMIT 1',
  )
    .bind(uid)
    .first<PlayerRow>();
  if (!player) {
    throw new ProductionVerificationError(
      404,
      'Player profile was not found.',
      'player_not_found',
    );
  }
  return player;
}

async function readPurchaseInput(request: Request): Promise<PurchaseInput> {
  let body: Record<string, unknown>;
  try {
    const parsed = await request.json();
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error();
    body = parsed as Record<string, unknown>;
  } catch {
    throw new ProductionVerificationError(400, 'Invalid JSON body.', 'invalid_json');
  }

  const productId = requiredString(body.productId, 'productId', 3, 80);
  const transactionId = requiredString(body.transactionId, 'transactionId', 1, 1024);
  const verificationData = requiredString(
    body.verificationData,
    'verificationData',
    1,
    24_000,
  );
  if (!COIN_PRODUCTS[productId] && !isNoAdsProductId(productId)) {
    throw new ProductionVerificationError(400, 'Unknown store product.', 'unknown_product');
  }
  return { productId, transactionId, verificationData };
}

async function verifyGooglePlayPurchase(
  env: ProductionPurchaseEnv,
  input: PurchaseInput,
): Promise<VerifiedPurchase> {
  const packageName = requireEnv(
    env.GOOGLE_PLAY_PACKAGE_NAME,
    'Google Play package name is not configured.',
  );
  const purchaseToken = input.verificationData.trim();
  const accessToken = await googlePlayAccessToken(env, false);
  let response = await fetchGooglePurchase(packageName, purchaseToken, accessToken);
  if (response.status === 401) {
    response = await fetchGooglePurchase(
      packageName,
      purchaseToken,
      await googlePlayAccessToken(env, true),
    );
  }
  if (!response.ok) {
    const message = await safeResponseText(response);
    throw new ProductionVerificationError(
      response.status === 404 ? 404 : 502,
      `Google Play could not verify this purchase.${message ? ` ${message}` : ''}`,
      'google_verification_failed',
    );
  }

  const purchase = (await response.json()) as Record<string, unknown>;
  const state = asObject(purchase.purchaseStateContext)?.purchaseState;
  if (state !== 'PURCHASED') {
    throw new ProductionVerificationError(
      409,
      state === 'PENDING'
        ? 'The Google Play purchase is still pending.'
        : 'The Google Play purchase is not active.',
      state === 'PENDING' ? 'purchase_pending' : 'purchase_not_active',
    );
  }

  const lineItems = Array.isArray(purchase.productLineItem)
    ? purchase.productLineItem
    : [];
  const matchedItem = lineItems
    .map(asObject)
    .find((item) => item?.productId === input.productId);
  if (!matchedItem) {
    throw new ProductionVerificationError(
      409,
      'The Google Play product does not match the requested product.',
      'product_mismatch',
    );
  }

  const completionTime = stringOrNull(purchase.purchaseCompletionTime);
  const orderId = stringOrNull(purchase.orderId);
  const testContext = asObject(purchase.testPurchaseContext);
  const storeEnvironment = testContext?.fopType === 'TEST' ? 'sandbox' : 'production';

  return {
    platform: 'android',
    productId: input.productId,
    transactionId: purchaseToken,
    verificationData: purchaseToken,
    purchasedAt: completionTime,
    storeEnvironment,
    storeOrderId: orderId,
    verificationSource: 'google_play_developer_api_v2',
    productType: isNoAdsProductId(input.productId) ? 'non_consumable' : 'consumable',
    consume:
      isNoAdsProductId(input.productId)
        ? undefined
        : async () => consumeGooglePurchase(env, packageName, input.productId, purchaseToken),
  };
}

async function fetchGooglePurchase(
  packageName: string,
  purchaseToken: string,
  accessToken: string,
): Promise<Response> {
  const url =
    'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/' +
    `${encodeURIComponent(packageName)}/purchases/productsv2/tokens/` +
    encodeURIComponent(purchaseToken);
  return fetch(url, {
    method: 'GET',
    headers: {
      authorization: `Bearer ${accessToken}`,
      accept: 'application/json',
    },
  });
}

async function consumeGooglePurchase(
  env: ProductionPurchaseEnv,
  packageName: string,
  productId: string,
  purchaseToken: string,
): Promise<boolean> {
  const accessToken = await googlePlayAccessToken(env, false);
  const url =
    'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/' +
    `${encodeURIComponent(packageName)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:consume`;
  let response = await fetch(url, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
    },
    body: '{}',
  });
  if (response.status === 401) {
    response = await fetch(url, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${await googlePlayAccessToken(env, true)}`,
        'content-type': 'application/json',
      },
      body: '{}',
    });
  }
  if (response.ok) return true;
  const text = await safeResponseText(response);
  if (response.status === 409 && /already|consum/i.test(text)) return true;
  console.error('Google Play consume response', response.status, text);
  return false;
}

async function googlePlayAccessToken(
  env: ProductionPurchaseEnv,
  forceRefresh: boolean,
): Promise<string> {
  if (
    !forceRefresh &&
    cachedGoogleAccessToken &&
    cachedGoogleAccessToken.expiresAt > Date.now() + 60_000
  ) {
    return cachedGoogleAccessToken.value;
  }

  const email = requireEnv(
    env.GOOGLE_PLAY_CLIENT_EMAIL,
    'Google Play service-account email is not configured.',
  );
  const privateKey = requireEnv(
    env.GOOGLE_PLAY_PRIVATE_KEY,
    'Google Play service-account private key is not configured.',
  ).replace(/\\n/g, '\n');
  const key = await importPKCS8(privateKey, 'RS256');
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: 'https://www.googleapis.com/auth/androidpublisher',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(email)
    .setSubject(email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!tokenResponse.ok) {
    throw new ProductionVerificationError(
      503,
      'Google Play verification credentials were rejected.',
      'google_credentials_rejected',
    );
  }
  const tokenBody = (await tokenResponse.json()) as Record<string, unknown>;
  const value = stringOrNull(tokenBody.access_token);
  const expiresIn = Number(tokenBody.expires_in ?? 3600);
  if (!value) {
    throw new ProductionVerificationError(
      503,
      'Google Play access token was not returned.',
      'google_token_missing',
    );
  }
  cachedGoogleAccessToken = {
    value,
    expiresAt: Date.now() + Math.max(300, expiresIn) * 1000,
  };
  return value;
}

async function verifyAppStorePurchase(
  env: ProductionPurchaseEnv,
  input: PurchaseInput,
): Promise<VerifiedPurchase> {
  const bundleId = requireEnv(
    env.APPLE_BUNDLE_ID,
    'Apple bundle ID is not configured.',
  );
  const clientPayload = decodeStoreKitJws(input.verificationData, 'client transaction');
  const requestedTransactionId =
    stringOrNull(clientPayload.transactionId) ?? input.transactionId;
  if (!requestedTransactionId) {
    throw new ProductionVerificationError(
      400,
      'The App Store transaction identifier is missing.',
      'transaction_id_missing',
    );
  }

  const token = await appStoreApiToken(env, bundleId);
  const productionUrl =
    'https://api.storekit.apple.com/inApps/v1/transactions/' +
    encodeURIComponent(requestedTransactionId);
  let response = await fetch(productionUrl, {
    headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
  });
  let storeEnvironment = 'production';
  if (!response.ok && (response.status === 404 || response.status === 400)) {
    const sandboxUrl =
      'https://api.storekit-sandbox.apple.com/inApps/v1/transactions/' +
      encodeURIComponent(requestedTransactionId);
    response = await fetch(sandboxUrl, {
      headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
    });
    storeEnvironment = 'sandbox';
  }
  if (!response.ok) {
    const message = await safeResponseText(response);
    throw new ProductionVerificationError(
      response.status === 404 ? 404 : 502,
      `The App Store could not verify this transaction.${message ? ` ${message}` : ''}`,
      'apple_verification_failed',
    );
  }

  const body = (await response.json()) as Record<string, unknown>;
  const signedTransactionInfo = requiredString(
    body.signedTransactionInfo,
    'signedTransactionInfo',
    20,
    24_000,
  );
  const payload = decodeStoreKitJws(signedTransactionInfo, 'App Store transaction');
  const transactionId = requiredString(
    payload.transactionId,
    'transactionId',
    1,
    1024,
  );
  const productId = requiredString(payload.productId, 'productId', 3, 80);
  const verifiedBundleId = requiredString(payload.bundleId, 'bundleId', 3, 255);
  if (transactionId !== requestedTransactionId) {
    throw new ProductionVerificationError(
      409,
      'The App Store transaction identifier does not match.',
      'transaction_mismatch',
    );
  }
  if (productId !== input.productId) {
    throw new ProductionVerificationError(
      409,
      'The App Store product does not match the requested product.',
      'product_mismatch',
    );
  }
  if (verifiedBundleId !== bundleId) {
    throw new ProductionVerificationError(
      409,
      'The App Store bundle identifier does not match this app.',
      'bundle_mismatch',
    );
  }
  if (payload.revocationDate != null || payload.revocationReason != null) {
    throw new ProductionVerificationError(
      409,
      'This App Store transaction has been revoked.',
      'purchase_revoked',
    );
  }
  const ownership = stringOrNull(payload.inAppOwnershipType);
  if (ownership && ownership !== 'PURCHASED') {
    throw new ProductionVerificationError(
      409,
      'This App Store transaction is not owned by the current purchaser.',
      'purchase_not_owned',
    );
  }
  const productType = stringOrNull(payload.type);
  const expectedType = isNoAdsProductId(productId) ? 'non-consumable' : 'consumable';
  if (productType && productType.toLowerCase() !== expectedType) {
    throw new ProductionVerificationError(
      409,
      'The App Store product is not configured with the expected type.',
      'product_type_mismatch',
    );
  }

  const purchaseDate = Number(payload.purchaseDate);
  return {
    platform: 'ios',
    productId,
    transactionId,
    verificationData: signedTransactionInfo,
    purchasedAt: Number.isFinite(purchaseDate)
      ? new Date(purchaseDate).toISOString()
      : null,
    storeEnvironment:
      stringOrNull(payload.environment)?.toLowerCase() ?? storeEnvironment,
    storeOrderId: stringOrNull(payload.originalTransactionId),
    verificationSource: 'app_store_server_api_transaction_info',
    productType: isNoAdsProductId(productId) ? 'non_consumable' : 'consumable',
  };
}

async function appStoreApiToken(
  env: ProductionPurchaseEnv,
  bundleId: string,
): Promise<string> {
  const issuerId = requireEnv(
    env.APPLE_IAP_ISSUER_ID,
    'Apple In-App Purchase issuer ID is not configured.',
  );
  const keyId = requireEnv(
    env.APPLE_IAP_KEY_ID,
    'Apple In-App Purchase key ID is not configured.',
  );
  const privateKey = requireEnv(
    env.APPLE_IAP_PRIVATE_KEY,
    'Apple In-App Purchase private key is not configured.',
  ).replace(/\\n/g, '\n');
  const key = await importPKCS8(privateKey, 'ES256');
  const now = Math.floor(Date.now() / 1000);
  return new SignJWT({ bid: bundleId })
    .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
    .setIssuer(issuerId)
    .setAudience('appstoreconnect-v1')
    .setIssuedAt(now)
    .setExpirationTime(now + 300)
    .sign(key);
}

async function grantVerifiedPurchase(
  env: ProductionPurchaseEnv,
  playerId: string,
  purchase: VerifiedPurchase,
): Promise<boolean> {
  if (isNoAdsProductId(purchase.productId)) {
    return grantNoAdsEntitlement(env, playerId, purchase);
  }
  const amount = COIN_PRODUCTS[purchase.productId];
  if (!amount) {
    throw new ProductionVerificationError(400, 'Unknown Coin product.', 'unknown_product');
  }
  const verificationHash = await sha256Hex(
    `${purchase.platform}:${purchase.transactionId}:${purchase.verificationData}`,
  );
  const existing = await env.DB.prepare(
    `SELECT player_id FROM purchase_grants
     WHERE transaction_id = ? OR verification_hash = ? LIMIT 1`,
  )
    .bind(purchase.transactionId, verificationHash)
    .first<{ player_id: string }>();
  if (existing) {
    if (existing.player_id !== playerId) {
      throw new ProductionVerificationError(
        409,
        'This store transaction has already been used by another player.',
        'purchase_replayed',
      );
    }
    return false;
  }

  const now = new Date().toISOString();
  const idempotencyKey = `store_purchase:${purchase.platform}:${purchase.transactionId}`;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO purchase_grants (
         id, player_id, platform, product_id, transaction_id,
         verification_hash, coins, status, purchased_at, granted_at,
         updated_at, store_environment, store_order_id, verification_source
       ) VALUES (?, ?, ?, ?, ?, ?, ?, 'verified', ?, ?, ?, ?, ?, ?)`,
    ).bind(
      crypto.randomUUID(),
      playerId,
      purchase.platform,
      purchase.productId,
      purchase.transactionId,
      verificationHash,
      amount,
      purchase.purchasedAt,
      now,
      now,
      purchase.storeEnvironment,
      purchase.storeOrderId,
      purchase.verificationSource,
    ),
    env.DB.prepare(
      `UPDATE players SET online_coins = online_coins + ?, updated_at = ?
       WHERE id = ?`,
    ).bind(amount, now, playerId),
    env.DB.prepare(
      `INSERT INTO coin_ledger (
         id, player_id, amount, balance_after, reason,
         reference_type, reference_id, idempotency_key, metadata_json, created_at
       ) VALUES (?, ?, ?, (SELECT online_coins FROM players WHERE id = ?),
                 'store_purchase', 'purchase', ?, ?, ?, ?)`,
    ).bind(
      crypto.randomUUID(),
      playerId,
      amount,
      playerId,
      purchase.transactionId,
      idempotencyKey,
      JSON.stringify({
        productId: purchase.productId,
        platform: purchase.platform,
        storeEnvironment: purchase.storeEnvironment,
        verificationSource: purchase.verificationSource,
      }),
      now,
    ),
  ]);
  return true;
}

async function grantNoAdsEntitlement(
  env: ProductionPurchaseEnv,
  playerId: string,
  purchase: VerifiedPurchase,
): Promise<boolean> {
  const verificationHash = await sha256Hex(
    `${purchase.platform}:${purchase.transactionId}:${purchase.verificationData}`,
  );
  const existing = await env.DB.prepare(
    `SELECT player_id FROM player_entitlements
     WHERE entitlement_key = 'no_ads'
       AND (source_transaction_id = ? OR verification_hash = ?)
     LIMIT 1`,
  )
    .bind(purchase.transactionId, verificationHash)
    .first<{ player_id: string }>();
  if (existing) {
    if (existing.player_id !== playerId) {
      throw new ProductionVerificationError(
        409,
        'This store transaction has already been used by another player.',
        'purchase_replayed',
      );
    }
    return false;
  }

  const now = new Date().toISOString();
  const inserted = await env.DB.prepare(
    `INSERT INTO player_entitlements (
       id, player_id, entitlement_key, source, source_transaction_id,
       verification_hash, granted_at, updated_at, metadata_json
     ) VALUES (?, ?, 'no_ads', ?, ?, ?, ?, ?, ?)
     ON CONFLICT(player_id, entitlement_key) DO UPDATE SET
       source = excluded.source,
       source_transaction_id = excluded.source_transaction_id,
       verification_hash = excluded.verification_hash,
       revoked_at = NULL,
       updated_at = excluded.updated_at,
       metadata_json = excluded.metadata_json`,
  )
    .bind(
      crypto.randomUUID(),
      playerId,
      purchase.platform,
      purchase.transactionId,
      verificationHash,
      now,
      now,
      JSON.stringify({
        productId: purchase.productId,
        platform: purchase.platform,
        storeEnvironment: purchase.storeEnvironment,
        verificationSource: purchase.verificationSource,
      }),
    )
    .run();
  return (inserted.meta.changes ?? 0) > 0;
}

function decodeStoreKitJws(
  value: string,
  label: string,
): Record<string, unknown> {
  try {
    const payload = decodeJwt(value);
    return payload as Record<string, unknown>;
  } catch {
    throw new ProductionVerificationError(
      400,
      `The ${label} is not a valid StoreKit 2 signed transaction.`,
      'invalid_apple_transaction',
    );
  }
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function requiredString(
  value: unknown,
  field: string,
  min: number,
  max: number,
): string {
  if (typeof value !== 'string') {
    throw new ProductionVerificationError(400, `${field} is required.`, 'invalid_request');
  }
  const result = value.trim();
  if (result.length < min || result.length > max) {
    throw new ProductionVerificationError(
      400,
      `${field} has an invalid length.`,
      'invalid_request',
    );
  }
  return result;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function requireEnv(value: string | undefined, message: string): string {
  const result = value?.trim();
  if (!result || result.startsWith('REPLACE_')) {
    throw new ProductionVerificationError(
      503,
      message,
      'purchase_verification_unavailable',
    );
  }
  return result;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

async function safeResponseText(response: Response): Promise<string> {
  try {
    const text = (await response.text()).trim();
    return text.length > 500 ? text.slice(0, 500) : text;
  } catch {
    return '';
  }
}
