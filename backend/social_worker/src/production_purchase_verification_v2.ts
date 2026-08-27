import {
  SignJWT,
  createRemoteJWKSet,
  decodeJwt,
  importPKCS8,
  jwtVerify,
} from 'jose';

import { verifyAppCheckRequest } from './app_check';
import {
  AppleJwsVerificationError,
  verifyAppleStoreKitJws,
} from './apple_jws_verifier';
import {
  acknowledgeGoogleProductPurchase,
  consumeGoogleProductPurchase,
  googlePlayAccessToken,
} from './google_play_lifecycle';

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
  ALLOW_UNVERIFIED_STORE_GRANTS?: string;
  APPLE_IAP_ISSUER_ID?: string;
  APPLE_IAP_KEY_ID?: string;
  APPLE_IAP_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID?: string;
  APPLE_ROOT_CERTIFICATES_PEM?: string;
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
  acknowledge?: () => Promise<boolean>;
};

type PlayerRow = {
  id: string;
  firebase_uid: string;
};

type ExistingPurchaseRow = {
  player_id: string;
  product_id: string;
};

type PendingLifecycleRow = {
  transaction_id: string;
  product_id: string;
};

export type PurchaseVerificationResult = {
  playerId: string;
  granted: boolean;
  consumed: boolean | null;
  acknowledged: boolean | null;
};

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
): Promise<PurchaseVerificationResult> {
  assertProductionEnvironment(env);
  if (request.method !== 'POST') {
    throw new ProductionVerificationError(
      405,
      'Method not allowed.',
      'method_not_allowed',
    );
  }

  await verifyAppCheckRequest(request, env);
  const player = await authenticatePlayer(request, env);
  const pathname = new URL(request.url).pathname;
  const platform = pathname.includes('/google/') ? 'android' : 'ios';
  const input = await readPurchaseInput(request, platform);
  const verified = platform === 'android'
    ? await verifyGooglePlayPurchaseOrEmergencyGrant(env, input)
    : await verifyAppStorePurchase(env, input);

  const granted = await grantVerifiedPurchase(env, player.id, verified);
  const lifecycle = await finalizeStoreLifecycle(env, verified);
  return {
    playerId: player.id,
    granted,
    consumed: lifecycle.consumed,
    acknowledged: lifecycle.acknowledged,
  };
}

async function verifyGooglePlayPurchaseOrEmergencyGrant(
  env: ProductionPurchaseEnv,
  input: PurchaseInput,
): Promise<VerifiedPurchase> {
  try {
    return await verifyGooglePlayPurchase(env, input);
  } catch (error) {
    if (
      isGooglePlayCredentialUnavailable(error) &&
      env.ALLOW_UNVERIFIED_STORE_GRANTS === 'true' &&
      COIN_PRODUCTS[input.productId]
    ) {
      console.warn('google_play_unverified_coin_grant_enabled', {
        productId: input.productId,
      });
      const purchaseToken = input.verificationData.trim();
      return {
        platform: 'android',
        productId: input.productId,
        transactionId: purchaseToken,
        verificationData: purchaseToken,
        purchasedAt: null,
        storeEnvironment: 'unverified',
        storeOrderId: input.transactionId,
        verificationSource: 'emergency_unverified_google_play_token',
        productType: 'consumable',
      };
    }
    throw error;
  }
}

function isGooglePlayCredentialUnavailable(error: unknown): boolean {
  if (
    error instanceof ProductionVerificationError &&
    error.code === 'purchase_verification_unavailable'
  ) {
    return true;
  }
  const message = error instanceof Error ? error.message : String(error);
  return /Google Play .*not configured|Google Play verification credentials/i.test(
    message,
  );
}

export async function reconcilePendingGooglePurchases(
  env: ProductionPurchaseEnv,
  limit = 50,
): Promise<{
  scanned: number;
  acknowledged: number;
  consumed: number;
  failed: number;
}> {
  assertProductionEnvironment(env);
  const packageName = requireEnv(
    env.GOOGLE_PLAY_PACKAGE_NAME,
    'Google Play package name is not configured.',
  );
  const safeLimit = Math.min(Math.max(Math.trunc(limit), 1), 200);
  const result = {
    scanned: 0,
    acknowledged: 0,
    consumed: 0,
    failed: 0,
  };

  const pendingAcknowledgements = await env.DB.prepare(
    `SELECT transaction_id, product_id
     FROM purchase_grants
     WHERE platform = 'android'
       AND product_id = ?
       AND acknowledge_status IN ('pending', 'failed')
     ORDER BY updated_at ASC
     LIMIT ?`,
  )
    .bind(NO_ADS_PRODUCT_ID, safeLimit)
    .all<PendingLifecycleRow>();

  for (const row of pendingAcknowledgements.results ?? []) {
    result.scanned++;
    try {
      await acknowledgeGoogleProductPurchase(
        env,
        packageName,
        row.product_id,
        row.transaction_id,
      );
      await markAcknowledged(env, row.transaction_id);
      result.acknowledged++;
    } catch (error) {
      await markAcknowledgeFailed(env, row.transaction_id, error);
      result.failed++;
    }
  }

  const remaining = Math.max(0, safeLimit - result.scanned);
  if (remaining === 0) return result;
  const pendingConsumptions = await env.DB.prepare(
    `SELECT transaction_id, product_id
     FROM purchase_grants
     WHERE platform = 'android'
       AND product_id <> ?
       AND consumed_at IS NULL
     ORDER BY updated_at ASC
     LIMIT ?`,
  )
    .bind(NO_ADS_PRODUCT_ID, remaining)
    .all<PendingLifecycleRow>();

  for (const row of pendingConsumptions.results ?? []) {
    result.scanned++;
    try {
      await consumeGoogleProductPurchase(
        env,
        packageName,
        row.product_id,
        row.transaction_id,
      );
      await markConsumed(env, row.transaction_id);
      result.consumed++;
    } catch (error) {
      await touchLifecycleFailure(env, row.transaction_id, error);
      result.failed++;
    }
  }
  return result;
}

function assertProductionEnvironment(env: ProductionPurchaseEnv): void {
  if ((env.ENVIRONMENT ?? '').toLowerCase() !== 'production') {
    throw new ProductionVerificationError(
      400,
      'Production purchase verification was called outside production.',
      'invalid_environment',
    );
  }
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

async function readPurchaseInput(
  request: Request,
  platform: 'android' | 'ios',
): Promise<PurchaseInput> {
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
    platform === 'ios' ? 128_000 : 24_000,
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
  let response = await fetchGooglePurchase(
    packageName,
    purchaseToken,
    await googlePlayAccessToken(env),
  );
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
  const noAds = isNoAdsProductId(input.productId);

  return {
    platform: 'android',
    productId: input.productId,
    transactionId: purchaseToken,
    verificationData: purchaseToken,
    purchasedAt: completionTime,
    storeEnvironment,
    storeOrderId: orderId,
    verificationSource: 'google_play_developer_api_v2',
    productType: noAds ? 'non_consumable' : 'consumable',
    acknowledge: noAds
      ? () => acknowledgeGoogleProductPurchase(
          env,
          packageName,
          input.productId,
          purchaseToken,
        )
      : undefined,
    consume: noAds
      ? undefined
      : () => consumeGoogleProductPurchase(
          env,
          packageName,
          input.productId,
          purchaseToken,
        ),
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

async function verifyAppStorePurchase(
  env: ProductionPurchaseEnv,
  input: PurchaseInput,
): Promise<VerifiedPurchase> {
  const bundleId = requireEnv(
    env.APPLE_BUNDLE_ID,
    'Apple bundle ID is not configured.',
  );
  const clientPayload = tryDecodeUntrustedStoreKitJws(input.verificationData);
  const requestedTransactionId =
    stringOrNull(clientPayload?.transactionId) ?? input.transactionId;
  if (!requestedTransactionId) {
    throw new ProductionVerificationError(
      400,
      'The App Store transaction identifier is missing.',
      'transaction_id_missing',
    );
  }

  const directReceiptFallback = await verifyAppStoreReceiptFallback(
    env,
    input,
    bundleId,
    requestedTransactionId,
  );
  if (directReceiptFallback) return directReceiptFallback;

  let token: string;
  try {
    token = await appStoreApiToken(env, bundleId);
  } catch (error) {
    const receiptFallback = await verifyAppStoreReceiptFallback(
      env,
      input,
      bundleId,
      requestedTransactionId,
    );
    if (receiptFallback) return receiptFallback;
    throw error;
  }
  const productionUrl =
    'https://api.storekit.apple.com/inApps/v1/transactions/' +
    encodeURIComponent(requestedTransactionId);
  let response = await fetch(productionUrl, {
    headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
  });
  let expectedEnvironment: 'production' | 'sandbox' = 'production';
  if (
    !response.ok &&
    (
      response.status === 400 ||
      response.status === 401 ||
      response.status === 404
    )
  ) {
    const sandboxUrl =
      'https://api.storekit-sandbox.apple.com/inApps/v1/transactions/' +
      encodeURIComponent(requestedTransactionId);
    response = await fetch(sandboxUrl, {
      headers: { authorization: `Bearer ${token}`, accept: 'application/json' },
    });
    expectedEnvironment = 'sandbox';
  }
  if (!response.ok) {
    const receiptFallback = await verifyAppStoreReceiptFallback(
      env,
      input,
      bundleId,
      requestedTransactionId,
    );
    if (receiptFallback) return receiptFallback;

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

  let payload: Record<string, unknown>;
  try {
    const rootCertificates = requireEnv(
      env.APPLE_ROOT_CERTIFICATES_PEM,
      'Trusted Apple root certificates are not configured.',
    );
    payload = await verifyAppleStoreKitJws(signedTransactionInfo, {
      trustedRootCertificatesPem: rootCertificates,
      expectedBundleId: bundleId,
      expectedEnvironment,
    });
  } catch (error) {
    if (error instanceof AppleJwsVerificationError) {
      throw new ProductionVerificationError(409, error.message, error.code);
    }
    throw error;
  }

  const transactionId = requiredString(
    payload.transactionId,
    'transactionId',
    1,
    1024,
  );
  const productId = requiredString(payload.productId, 'productId', 3, 80);
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
    storeEnvironment: expectedEnvironment,
    storeOrderId: stringOrNull(payload.originalTransactionId),
    verificationSource: 'app_store_server_api_verified_jws',
    productType: isNoAdsProductId(productId) ? 'non_consumable' : 'consumable',
  };
}

async function verifyAppStoreReceiptFallback(
  env: ProductionPurchaseEnv,
  input: PurchaseInput,
  bundleId: string,
  requestedTransactionId: string,
): Promise<VerifiedPurchase | null> {
  if (!looksLikeAppStoreReceipt(input.verificationData)) return null;

  let receiptResponse = await fetchAppStoreReceipt(
    'https://buy.itunes.apple.com/verifyReceipt',
    input.verificationData,
  );
  let receiptBody = await parseAppStoreReceiptResponse(receiptResponse);
  let storeEnvironment = receiptEnvironment(receiptBody) ?? 'production';

  if (receiptStatus(receiptBody) === 21007) {
    receiptResponse = await fetchAppStoreReceipt(
      'https://sandbox.itunes.apple.com/verifyReceipt',
      input.verificationData,
    );
    receiptBody = await parseAppStoreReceiptResponse(receiptResponse);
    storeEnvironment = receiptEnvironment(receiptBody) ?? 'sandbox';
  } else if (receiptStatus(receiptBody) === 21008) {
    receiptResponse = await fetchAppStoreReceipt(
      'https://buy.itunes.apple.com/verifyReceipt',
      input.verificationData,
    );
    receiptBody = await parseAppStoreReceiptResponse(receiptResponse);
    storeEnvironment = receiptEnvironment(receiptBody) ?? 'production';
  }

  if (receiptStatus(receiptBody) !== 0) {
    throw new ProductionVerificationError(
      409,
      `The App Store receipt could not verify this purchase. status=${receiptStatus(receiptBody)}`,
      'apple_receipt_verification_failed',
    );
  }

  const receipt = asObject(receiptBody.receipt);
  const receiptBundleId = stringOrNull(receipt?.bundle_id);
  if (receiptBundleId !== bundleId) {
    throw new ProductionVerificationError(
      409,
      'The App Store receipt bundle does not match this app.',
      'bundle_mismatch',
    );
  }

  const inAppPurchases = Array.isArray(receipt?.in_app)
    ? receipt.in_app.map(asObject).filter((item): item is Record<string, unknown> => !!item)
    : [];
  const matchingProduct = inAppPurchases.filter(
    (item) => stringOrNull(item.product_id) === input.productId,
  );
  const selected =
    matchingProduct.find((item) => receiptTransactionMatches(item, requestedTransactionId)) ??
    matchingProduct.sort((a, b) => receiptPurchaseTime(b) - receiptPurchaseTime(a))[0];

  if (!selected) {
    throw new ProductionVerificationError(
      409,
      'The App Store receipt does not contain the requested product.',
      'product_mismatch',
    );
  }

  const transactionId = stringOrNull(selected.transaction_id);
  if (!transactionId) {
    throw new ProductionVerificationError(
      400,
      'The App Store receipt transaction identifier is missing.',
      'transaction_id_missing',
    );
  }
  if (
    selected.cancellation_date != null ||
    selected.cancellation_date_ms != null ||
    selected.cancellation_reason != null
  ) {
    throw new ProductionVerificationError(
      409,
      'This App Store transaction has been revoked.',
      'purchase_revoked',
    );
  }
  const ownership = stringOrNull(selected.in_app_ownership_type);
  if (ownership && ownership !== 'PURCHASED') {
    throw new ProductionVerificationError(
      409,
      'This App Store transaction is not owned by the current purchaser.',
      'purchase_not_owned',
    );
  }

  const purchaseDate = receiptPurchaseTime(selected);
  return {
    platform: 'ios',
    productId: input.productId,
    transactionId,
    verificationData: input.verificationData,
    purchasedAt: Number.isFinite(purchaseDate) && purchaseDate > 0
      ? new Date(purchaseDate).toISOString()
      : null,
    storeEnvironment,
    storeOrderId: stringOrNull(selected.original_transaction_id),
    verificationSource: 'app_store_verify_receipt',
    productType: isNoAdsProductId(input.productId) ? 'non_consumable' : 'consumable',
  };
}

async function fetchAppStoreReceipt(
  url: string,
  receiptData: string,
): Promise<Response> {
  return fetch(url, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      'receipt-data': receiptData,
      'exclude-old-transactions': false,
    }),
  });
}

async function parseAppStoreReceiptResponse(
  response: Response,
): Promise<Record<string, unknown>> {
  if (!response.ok) {
    const message = await safeResponseText(response);
    throw new ProductionVerificationError(
      502,
      `The App Store receipt endpoint did not respond successfully.${message ? ` ${message}` : ''}`,
      'apple_receipt_verification_failed',
    );
  }
  const body = await response.json();
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new ProductionVerificationError(
      502,
      'The App Store receipt endpoint returned an invalid response.',
      'apple_receipt_verification_failed',
    );
  }
  return body as Record<string, unknown>;
}

function looksLikeAppStoreReceipt(value: string): boolean {
  const clean = value.trim();
  return clean.length >= 100 && /^[A-Za-z0-9+/=]+$/.test(clean);
}

function receiptStatus(body: Record<string, unknown>): number {
  const status = Number(body.status);
  return Number.isFinite(status) ? status : -1;
}

function receiptEnvironment(body: Record<string, unknown>): string | null {
  const value = stringOrNull(body.environment)?.toLowerCase();
  if (!value) return null;
  return value === 'sandbox' ? 'sandbox' : 'production';
}

function receiptTransactionMatches(
  item: Record<string, unknown>,
  transactionId: string,
): boolean {
  return (
    stringOrNull(item.transaction_id) === transactionId ||
    stringOrNull(item.original_transaction_id) === transactionId
  );
}

function receiptPurchaseTime(item: Record<string, unknown>): number {
  return Number(stringOrNull(item.purchase_date_ms) ?? 0);
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
  const verificationHash = await sha256Hex(
    `${purchase.platform}:${purchase.transactionId}:${purchase.verificationData}`,
  );
  const existing = await findExistingPurchase(
    env,
    purchase.transactionId,
    verificationHash,
  );
  if (existing) {
    if (existing.player_id !== playerId) {
      throw new ProductionVerificationError(
        409,
        'This store transaction has already been used by another player.',
        'purchase_replayed',
      );
    }
    if (isNoAdsProductId(purchase.productId)) {
      await upsertNoAdsEntitlement(env, playerId, purchase, verificationHash);
    }
    return false;
  }

  if (isNoAdsProductId(purchase.productId)) {
    return grantNoAdsEntitlement(env, playerId, purchase, verificationHash);
  }
  return grantCoinPurchase(env, playerId, purchase, verificationHash);
}

async function findExistingPurchase(
  env: ProductionPurchaseEnv,
  transactionId: string,
  verificationHash: string,
): Promise<ExistingPurchaseRow | null> {
  return env.DB.prepare(
    `SELECT player_id, product_id FROM purchase_grants
     WHERE transaction_id = ? OR verification_hash = ? LIMIT 1`,
  )
    .bind(transactionId, verificationHash)
    .first<ExistingPurchaseRow>();
}

async function grantCoinPurchase(
  env: ProductionPurchaseEnv,
  playerId: string,
  purchase: VerifiedPurchase,
  verificationHash: string,
): Promise<boolean> {
  const amount = COIN_PRODUCTS[purchase.productId];
  if (!amount) {
    throw new ProductionVerificationError(400, 'Unknown Coin product.', 'unknown_product');
  }
  const now = new Date().toISOString();
  const idempotencyKey = `store_purchase:${purchase.platform}:${purchase.transactionId}`;
  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO purchase_grants (
           id, player_id, platform, product_id, transaction_id,
           verification_hash, coins, status, purchased_at, granted_at,
           updated_at, store_environment, store_order_id, verification_source,
           acknowledge_status
         ) VALUES (?, ?, ?, ?, ?, ?, ?, 'verified', ?, ?, ?, ?, ?, ?, 'not_required')`,
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
  } catch (error) {
    if (!isPurchaseUniqueConstraintError(error)) throw error;
    const existing = await findExistingPurchase(
      env,
      purchase.transactionId,
      verificationHash,
    );
    if (existing?.player_id === playerId) return false;
    throw new ProductionVerificationError(
      409,
      'This store transaction has already been used by another player.',
      'purchase_replayed',
    );
  }
  return true;
}

async function grantNoAdsEntitlement(
  env: ProductionPurchaseEnv,
  playerId: string,
  purchase: VerifiedPurchase,
  verificationHash: string,
): Promise<boolean> {
  const legacyOwner = await env.DB.prepare(
    `SELECT player_id FROM player_entitlements
     WHERE entitlement_key = 'no_ads'
       AND (source_transaction_id = ? OR verification_hash = ?)
     LIMIT 1`,
  )
    .bind(purchase.transactionId, verificationHash)
    .first<{ player_id: string }>();
  if (legacyOwner && legacyOwner.player_id !== playerId) {
    throw new ProductionVerificationError(
      409,
      'This store transaction has already been used by another player.',
      'purchase_replayed',
    );
  }

  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO purchase_grants (
         id, player_id, platform, product_id, transaction_id,
         verification_hash, coins, status, purchased_at, granted_at,
         updated_at, store_environment, store_order_id, verification_source,
         acknowledge_status
       ) VALUES (?, ?, ?, ?, ?, ?, 0, 'verified', ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      crypto.randomUUID(),
      playerId,
      purchase.platform,
      purchase.productId,
      purchase.transactionId,
      verificationHash,
      purchase.purchasedAt,
      now,
      now,
      purchase.storeEnvironment,
      purchase.storeOrderId,
      purchase.verificationSource,
      purchase.platform === 'android' ? 'pending' : 'not_required',
    ),
    entitlementUpsertStatement(env, playerId, purchase, verificationHash, now),
    env.DB.prepare(
      `INSERT OR IGNORE INTO entitlement_events (
         id, player_id, entitlement_key, action, source,
         source_event_id, source_transaction_id, metadata_json, created_at
       ) VALUES (?, ?, 'no_ads', 'grant', ?, ?, ?, ?, ?)`,
    ).bind(
      crypto.randomUUID(),
      playerId,
      purchase.platform,
      purchase.transactionId,
      purchase.transactionId,
      JSON.stringify({ productId: purchase.productId }),
      now,
    ),
  ]);
  return true;
}

async function upsertNoAdsEntitlement(
  env: ProductionPurchaseEnv,
  playerId: string,
  purchase: VerifiedPurchase,
  verificationHash: string,
): Promise<void> {
  const now = new Date().toISOString();
  await entitlementUpsertStatement(
    env,
    playerId,
    purchase,
    verificationHash,
    now,
  ).run();
}

function entitlementUpsertStatement(
  env: ProductionPurchaseEnv,
  playerId: string,
  purchase: VerifiedPurchase,
  verificationHash: string,
  now: string,
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO player_entitlements (
       id, player_id, entitlement_key,
       source_platform, source_product_id,
       source_transaction_id, verification_hash,
       granted_at, updated_at
     ) VALUES (?, ?, 'no_ads', ?, ?, ?, ?, ?, ?)
     ON CONFLICT(player_id, entitlement_key) DO UPDATE SET
       source_platform = excluded.source_platform,
       source_product_id = excluded.source_product_id,
       source_transaction_id = excluded.source_transaction_id,
       verification_hash = excluded.verification_hash,
       revoked_at = NULL,
       updated_at = excluded.updated_at`,
  ).bind(
    crypto.randomUUID(),
    playerId,
    purchase.platform,
    purchase.productId,
    purchase.transactionId,
    verificationHash,
    now,
    now,
  );
}

async function finalizeStoreLifecycle(
  env: ProductionPurchaseEnv,
  purchase: VerifiedPurchase,
): Promise<{ consumed: boolean | null; acknowledged: boolean | null }> {
  let consumed: boolean | null = null;
  let acknowledged: boolean | null = null;

  if (purchase.consume) {
    try {
      consumed = await purchase.consume();
      if (consumed) await markConsumed(env, purchase.transactionId);
    } catch (error) {
      consumed = false;
      await touchLifecycleFailure(env, purchase.transactionId, error);
      console.error('Google Play purchase consumption failed', error);
    }
  }

  if (purchase.acknowledge) {
    try {
      acknowledged = await purchase.acknowledge();
      if (acknowledged) await markAcknowledged(env, purchase.transactionId);
    } catch (error) {
      acknowledged = false;
      await markAcknowledgeFailed(env, purchase.transactionId, error);
      console.error('Google Play purchase acknowledgement failed', error);
    }
  }
  return { consumed, acknowledged };
}

async function markConsumed(
  env: ProductionPurchaseEnv,
  transactionId: string,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE purchase_grants
     SET consumed_at = COALESCE(consumed_at, ?), updated_at = ?
     WHERE platform = 'android' AND transaction_id = ?`,
  )
    .bind(now, now, transactionId)
    .run();
}

async function markAcknowledged(
  env: ProductionPurchaseEnv,
  transactionId: string,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE purchase_grants
     SET acknowledged_at = COALESCE(acknowledged_at, ?),
         acknowledge_status = 'acknowledged',
         acknowledge_error = NULL,
         updated_at = ?
     WHERE platform = 'android' AND transaction_id = ?`,
  )
    .bind(now, now, transactionId)
    .run();
}

async function markAcknowledgeFailed(
  env: ProductionPurchaseEnv,
  transactionId: string,
  error: unknown,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE purchase_grants
     SET acknowledge_status = 'failed', acknowledge_error = ?, updated_at = ?
     WHERE platform = 'android' AND transaction_id = ?`,
  )
    .bind(errorMessage(error), now, transactionId)
    .run();
}

async function touchLifecycleFailure(
  env: ProductionPurchaseEnv,
  transactionId: string,
  error: unknown,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE purchase_grants SET updated_at = ?
     WHERE platform = 'android' AND transaction_id = ?`,
  )
    .bind(now, transactionId)
    .run();
  console.error('purchase_lifecycle_retry_required', {
    transactionId,
    message: errorMessage(error),
  });
}

function tryDecodeUntrustedStoreKitJws(value: string): Record<string, unknown> | null {
  try {
    const payload = decodeJwt(value);
    return payload as Record<string, unknown>;
  } catch {
    return null;
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

function errorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.length > 500 ? message.slice(0, 500) : message;
}

function isPurchaseUniqueConstraintError(error: unknown): boolean {
  return /unique constraint failed: purchase_grants\.(transaction_id|verification_hash)/i.test(
    errorMessage(error),
  );
}
