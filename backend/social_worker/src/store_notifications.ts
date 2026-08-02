import { createRemoteJWKSet, decodeJwt, jwtVerify } from 'jose';

import { verifyAppleStoreKitJws } from './apple_jws_verifier';
import type { ProductionPurchaseEnv } from './production_purchase_verification_v2';

const GOOGLE_OIDC_JWKS = createRemoteJWKSet(
  new URL('https://www.googleapis.com/oauth2/v3/certs'),
);
const NO_ADS_PRODUCT_ID = 'no_ads';

export type StoreNotificationEnv = ProductionPurchaseEnv & {
  GOOGLE_PUBSUB_AUDIENCE?: string;
  GOOGLE_PUBSUB_SERVICE_ACCOUNT?: string;
};

type PurchaseGrantRow = {
  id: string;
  player_id: string;
  platform: string;
  product_id: string;
  transaction_id: string;
  store_order_id: string | null;
  coins: number;
  status: string;
  refund_status: string;
  refunded_coins: number;
  unrecovered_coins: number;
};

type PlayerBalanceRow = {
  online_coins: number;
};

export class StoreNotificationError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

export function isGooglePlayRtdnPath(pathname: string): boolean {
  return pathname === '/v1/store/google/rtdn';
}

export function isAppleServerNotificationPath(pathname: string): boolean {
  return pathname === '/v1/store/apple/notifications';
}

export async function handleGooglePlayRtdn(
  request: Request,
  env: StoreNotificationEnv,
): Promise<Response> {
  assertProduction(env);
  if (request.method !== 'POST') {
    throw new StoreNotificationError(405, 'Method not allowed.', 'method_not_allowed');
  }
  await verifyGooglePubSubIdentity(request, env);

  const body = await parseJsonObject(request);
  const message = asObject(body.message);
  const messageId = stringValue(message?.messageId);
  const encoded = stringValue(message?.data);
  if (!messageId || !encoded) {
    throw new StoreNotificationError(
      400,
      'The Pub/Sub message is incomplete.',
      'invalid_pubsub_message',
    );
  }

  const notification = parseBase64Json(encoded);
  const packageName = stringValue(notification.packageName);
  const expectedPackage = requiredEnv(
    env.GOOGLE_PLAY_PACKAGE_NAME,
    'Google Play package name is not configured.',
  );
  if (packageName !== expectedPackage) {
    throw new StoreNotificationError(
      409,
      'The Google Play package name does not match.',
      'package_mismatch',
    );
  }

  const eventHash = await sha256Hex(encoded);
  const inserted = await insertPurchaseEvent(env, {
    platform: 'android',
    eventId: messageId,
    eventType: googleEventType(notification),
    transactionId: googlePurchaseToken(notification),
    productId: googleProductId(notification),
    payloadHash: eventHash,
    payloadJson: JSON.stringify(notification),
  });
  if (!inserted) return new Response(null, { status: 204 });

  const voided = asObject(notification.voidedPurchaseNotification);
  if (voided) {
    const refundType = numberValue(voided.refundType);
    if (refundType === 2) {
      await markPurchaseEvent(
        env,
        'android',
        messageId,
        'review_required',
        'partial_refund',
        'Quantity-based partial refunds require quantity reconciliation.',
      );
      return new Response(null, { status: 204 });
    }
    const purchaseToken = requiredString(
      voided.purchaseToken,
      'purchaseToken',
    );
    const orderId = stringValue(voided.orderId);
    await applyPurchaseRevocation(env, {
      platform: 'android',
      transactionId: purchaseToken,
      storeOrderId: orderId,
      source: 'google_play_rtdn_voided',
      sourceEventId: messageId,
    });
    await markPurchaseEvent(env, 'android', messageId, 'processed');
    return new Response(null, { status: 204 });
  }

  const oneTime = asObject(notification.oneTimeProductNotification);
  if (oneTime) {
    const notificationType = numberValue(oneTime.notificationType);
    await markPurchaseEvent(
      env,
      'android',
      messageId,
      notificationType === 1 ? 'observed_purchase' : 'observed_cancellation',
    );
    return new Response(null, { status: 204 });
  }

  await markPurchaseEvent(env, 'android', messageId, 'ignored');
  return new Response(null, { status: 204 });
}

export async function handleAppleServerNotification(
  request: Request,
  env: StoreNotificationEnv,
): Promise<Response> {
  assertProduction(env);
  if (request.method !== 'POST') {
    throw new StoreNotificationError(405, 'Method not allowed.', 'method_not_allowed');
  }

  const body = await parseJsonObject(request);
  const signedPayload = requiredString(body.signedPayload, 'signedPayload');
  let outer: Record<string, unknown>;
  try {
    outer = decodeJwt(signedPayload) as Record<string, unknown>;
  } catch {
    throw new StoreNotificationError(
      400,
      'The App Store notification payload is invalid.',
      'invalid_apple_notification',
    );
  }

  const notificationUuid = requiredString(
    outer.notificationUUID,
    'notificationUUID',
  );
  const notificationType = requiredString(
    outer.notificationType,
    'notificationType',
  );
  const data = asObject(outer.data);
  const bundleId = stringValue(data?.bundleId);
  const expectedBundleId = requiredEnv(
    env.APPLE_BUNDLE_ID,
    'Apple bundle ID is not configured.',
  );
  if (bundleId !== expectedBundleId) {
    throw new StoreNotificationError(
      409,
      'The App Store notification bundle identifier does not match.',
      'bundle_mismatch',
    );
  }

  const signedTransactionInfo = stringValue(data?.signedTransactionInfo);
  const eventHash = await sha256Hex(signedPayload);
  const inserted = await insertPurchaseEvent(env, {
    platform: 'ios',
    eventId: notificationUuid,
    eventType: notificationType,
    transactionId: null,
    productId: null,
    payloadHash: eventHash,
    payloadJson: JSON.stringify({
      notificationType,
      subtype: stringValue(outer.subtype),
      signedDate: numberValue(outer.signedDate),
      data: {
        bundleId,
        environment: stringValue(data?.environment),
      },
    }),
  });
  if (!inserted) return new Response(null, { status: 200 });

  if (!signedTransactionInfo) {
    await markPurchaseEvent(env, 'ios', notificationUuid, 'ignored');
    return new Response(null, { status: 200 });
  }

  const trustedRoots = requiredEnv(
    env.APPLE_ROOT_CERTIFICATES_PEM,
    'Trusted Apple root certificates are not configured.',
  );
  const environment = stringValue(data?.environment)?.toLowerCase();
  const transaction = await verifyAppleStoreKitJws(signedTransactionInfo, {
    trustedRootCertificatesPem: trustedRoots,
    expectedBundleId,
    expectedEnvironment:
      environment === 'sandbox' || environment === 'production'
        ? environment
        : undefined,
  });
  const transactionId = requiredString(
    transaction.transactionId,
    'transactionId',
  );
  const originalTransactionId = stringValue(transaction.originalTransactionId);
  const productId = requiredString(transaction.productId, 'productId');
  await attachPurchaseEventIdentity(env, {
    platform: 'ios',
    eventId: notificationUuid,
    transactionId,
    productId,
  });

  if (notificationType === 'REFUND' || notificationType === 'REVOKE') {
    if (transaction.revocationDate == null && transaction.revocationReason == null) {
      throw new StoreNotificationError(
        409,
        'The signed App Store transaction is not revoked.',
        'revocation_not_verified',
      );
    }
    await applyPurchaseRevocation(env, {
      platform: 'ios',
      transactionId,
      storeOrderId: originalTransactionId,
      source: `app_store_${notificationType.toLowerCase()}`,
      sourceEventId: notificationUuid,
    });
    await markPurchaseEvent(env, 'ios', notificationUuid, 'processed');
    return new Response(null, { status: 200 });
  }

  if (notificationType === 'REFUND_REVERSED') {
    await reversePurchaseRevocation(env, {
      platform: 'ios',
      transactionId,
      storeOrderId: originalTransactionId,
      sourceEventId: notificationUuid,
    });
    await markPurchaseEvent(env, 'ios', notificationUuid, 'processed');
    return new Response(null, { status: 200 });
  }

  await markPurchaseEvent(env, 'ios', notificationUuid, 'ignored');
  return new Response(null, { status: 200 });
}

export async function applyPurchaseRevocation(
  env: StoreNotificationEnv,
  input: {
    platform: 'android' | 'ios';
    transactionId: string;
    storeOrderId?: string | null;
    source: string;
    sourceEventId: string;
  },
): Promise<boolean> {
  const purchase = await findPurchaseGrant(
    env,
    input.platform,
    input.transactionId,
    input.storeOrderId,
  );
  if (!purchase) return false;
  if (purchase.refund_status === 'refunded' || purchase.status === 'revoked') {
    return false;
  }

  const now = new Date().toISOString();
  if (purchase.product_id === NO_ADS_PRODUCT_ID) {
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE purchase_grants
         SET status = 'revoked', revoked_at = ?, revocation_source = ?,
             refund_status = 'refunded', updated_at = ?
         WHERE id = ?`,
      ).bind(now, input.source, now, purchase.id),
      env.DB.prepare(
        `UPDATE player_entitlements
         SET revoked_at = ?, updated_at = ?
         WHERE player_id = ? AND entitlement_key = 'no_ads'`,
      ).bind(now, now, purchase.player_id),
      env.DB.prepare(
        `INSERT OR IGNORE INTO entitlement_events (
           id, player_id, entitlement_key, action, source,
           source_event_id, source_transaction_id, metadata_json, created_at
         ) VALUES (?, ?, 'no_ads', 'revoke', ?, ?, ?, ?, ?)`,
      ).bind(
        crypto.randomUUID(),
        purchase.player_id,
        input.source,
        input.sourceEventId,
        purchase.transaction_id,
        JSON.stringify({ platform: input.platform }),
        now,
      ),
    ]);
    return true;
  }

  const player = await env.DB.prepare(
    'SELECT online_coins FROM players WHERE id = ? LIMIT 1',
  )
    .bind(purchase.player_id)
    .first<PlayerBalanceRow>();
  const balance = Math.max(0, player?.online_coins ?? 0);
  const purchasedCoins = Math.max(0, purchase.coins);
  const recovered = Math.min(balance, purchasedCoins);
  const debt = Math.max(0, purchasedCoins - recovered);
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `UPDATE purchase_grants
       SET status = 'revoked', revoked_at = ?, revocation_source = ?,
           refund_status = 'refunded', refunded_coins = ?,
           unrecovered_coins = ?, updated_at = ?
       WHERE id = ?`,
    ).bind(
      now,
      input.source,
      recovered,
      debt,
      now,
      purchase.id,
    ),
  ];
  if (recovered > 0) {
    statements.push(
      env.DB.prepare(
        `UPDATE players SET online_coins = MAX(0, online_coins - ?), updated_at = ?
         WHERE id = ?`,
      ).bind(recovered, now, purchase.player_id),
      env.DB.prepare(
        `INSERT INTO coin_ledger (
           id, player_id, amount, balance_after, reason,
           reference_type, reference_id, idempotency_key, metadata_json, created_at
         ) VALUES (?, ?, ?, (SELECT online_coins FROM players WHERE id = ?),
                   'purchase_refund', 'purchase', ?, ?, ?, ?)`,
      ).bind(
        crypto.randomUUID(),
        purchase.player_id,
        -recovered,
        purchase.player_id,
        purchase.transaction_id,
        `purchase_refund:${input.platform}:${purchase.transaction_id}`,
        JSON.stringify({
          source: input.source,
          purchasedCoins,
          recovered,
          debt,
        }),
        now,
      ),
    );
  }
  if (debt > 0) {
    statements.push(
      env.DB.prepare(
        `INSERT INTO player_coin_debts (
           player_id, amount, reason, source_transaction_id, updated_at, created_at
         ) VALUES (?, ?, 'purchase_refund', ?, ?, ?)
         ON CONFLICT(player_id) DO UPDATE SET
           amount = player_coin_debts.amount + excluded.amount,
           reason = excluded.reason,
           source_transaction_id = excluded.source_transaction_id,
           updated_at = excluded.updated_at`,
      ).bind(
        purchase.player_id,
        debt,
        purchase.transaction_id,
        now,
        now,
      ),
    );
  }
  await env.DB.batch(statements);
  return true;
}

export async function reversePurchaseRevocation(
  env: StoreNotificationEnv,
  input: {
    platform: 'android' | 'ios';
    transactionId: string;
    storeOrderId?: string | null;
    sourceEventId: string;
  },
): Promise<boolean> {
  const purchase = await findPurchaseGrant(
    env,
    input.platform,
    input.transactionId,
    input.storeOrderId,
  );
  if (!purchase || purchase.refund_status !== 'refunded') return false;
  const now = new Date().toISOString();

  if (purchase.product_id === NO_ADS_PRODUCT_ID) {
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE purchase_grants
         SET status = 'verified', revoked_at = NULL, revocation_source = NULL,
             refund_status = 'reversed', updated_at = ?
         WHERE id = ?`,
      ).bind(now, purchase.id),
      env.DB.prepare(
        `UPDATE player_entitlements
         SET revoked_at = NULL, updated_at = ?
         WHERE player_id = ? AND entitlement_key = 'no_ads'`,
      ).bind(now, purchase.player_id),
      env.DB.prepare(
        `INSERT OR IGNORE INTO entitlement_events (
           id, player_id, entitlement_key, action, source,
           source_event_id, source_transaction_id, metadata_json, created_at
         ) VALUES (?, ?, 'no_ads', 'restore', 'app_store_refund_reversed',
                   ?, ?, '{}', ?)`,
      ).bind(
        crypto.randomUUID(),
        purchase.player_id,
        input.sourceEventId,
        purchase.transaction_id,
        now,
      ),
    ]);
    return true;
  }

  const restored = Math.max(0, purchase.refunded_coins);
  const debtReduction = Math.max(0, purchase.unrecovered_coins);
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `UPDATE purchase_grants
       SET status = 'verified', revoked_at = NULL, revocation_source = NULL,
           refund_status = 'reversed', refunded_coins = 0,
           unrecovered_coins = 0, updated_at = ?
       WHERE id = ?`,
    ).bind(now, purchase.id),
  ];
  if (restored > 0) {
    statements.push(
      env.DB.prepare(
        `UPDATE players SET online_coins = online_coins + ?, updated_at = ?
         WHERE id = ?`,
      ).bind(restored, now, purchase.player_id),
      env.DB.prepare(
        `INSERT INTO coin_ledger (
           id, player_id, amount, balance_after, reason,
           reference_type, reference_id, idempotency_key, metadata_json, created_at
         ) VALUES (?, ?, ?, (SELECT online_coins FROM players WHERE id = ?),
                   'purchase_refund_reversed', 'purchase', ?, ?, '{}', ?)`,
      ).bind(
        crypto.randomUUID(),
        purchase.player_id,
        restored,
        purchase.player_id,
        purchase.transaction_id,
        `purchase_refund_reversed:${input.platform}:${purchase.transaction_id}`,
        now,
      ),
    );
  }
  if (debtReduction > 0) {
    statements.push(
      env.DB.prepare(
        `UPDATE player_coin_debts
         SET amount = MAX(0, amount - ?), updated_at = ?
         WHERE player_id = ?`,
      ).bind(debtReduction, now, purchase.player_id),
      env.DB.prepare(
        'DELETE FROM player_coin_debts WHERE player_id = ? AND amount <= 0',
      ).bind(purchase.player_id),
    );
  }
  await env.DB.batch(statements);
  return true;
}

async function verifyGooglePubSubIdentity(
  request: Request,
  env: StoreNotificationEnv,
): Promise<void> {
  const audience = requiredEnv(
    env.GOOGLE_PUBSUB_AUDIENCE,
    'Google Pub/Sub push audience is not configured.',
  );
  const expectedEmail = requiredEnv(
    env.GOOGLE_PUBSUB_SERVICE_ACCOUNT,
    'Google Pub/Sub service account is not configured.',
  );
  const authorization = request.headers.get('authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) {
    throw new StoreNotificationError(
      401,
      'Missing Pub/Sub bearer token.',
      'missing_pubsub_token',
    );
  }
  try {
    const verified = await jwtVerify(
      authorization.slice(7).trim(),
      GOOGLE_OIDC_JWKS,
      {
        issuer: ['https://accounts.google.com', 'accounts.google.com'],
        audience,
        algorithms: ['RS256'],
      },
    );
    const email = stringValue(verified.payload.email);
    const emailVerified = verified.payload.email_verified;
    if (email !== expectedEmail || emailVerified !== true) throw new Error();
  } catch {
    throw new StoreNotificationError(
      401,
      'Invalid Pub/Sub bearer token.',
      'invalid_pubsub_token',
    );
  }
}

async function findPurchaseGrant(
  env: StoreNotificationEnv,
  platform: string,
  transactionId: string,
  storeOrderId?: string | null,
): Promise<PurchaseGrantRow | null> {
  return env.DB.prepare(
    `SELECT id, player_id, platform, product_id, transaction_id,
            store_order_id, coins, status, refund_status,
            refunded_coins, unrecovered_coins
     FROM purchase_grants
     WHERE platform = ?
       AND (transaction_id = ? OR (? IS NOT NULL AND store_order_id = ?))
     ORDER BY granted_at DESC
     LIMIT 1`,
  )
    .bind(platform, transactionId, storeOrderId ?? null, storeOrderId ?? null)
    .first<PurchaseGrantRow>();
}

async function insertPurchaseEvent(
  env: StoreNotificationEnv,
  input: {
    platform: string;
    eventId: string;
    eventType: string;
    transactionId: string | null;
    productId: string | null;
    payloadHash: string;
    payloadJson: string;
  },
): Promise<boolean> {
  const now = new Date().toISOString();
  const result = await env.DB.prepare(
    `INSERT OR IGNORE INTO purchase_events (
       id, platform, event_id, event_type, transaction_id, product_id,
       status, payload_hash, payload_json, created_at, updated_at
     ) VALUES (?, ?, ?, ?, ?, ?, 'received', ?, ?, ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      input.platform,
      input.eventId,
      input.eventType,
      input.transactionId,
      input.productId,
      input.payloadHash,
      input.payloadJson,
      now,
      now,
    )
    .run();
  return Number(result.meta.changes ?? 0) > 0;
}

async function attachPurchaseEventIdentity(
  env: StoreNotificationEnv,
  input: {
    platform: string;
    eventId: string;
    transactionId: string;
    productId: string;
  },
): Promise<void> {
  await env.DB.prepare(
    `UPDATE purchase_events
     SET transaction_id = ?, product_id = ?, updated_at = ?
     WHERE platform = ? AND event_id = ?`,
  )
    .bind(
      input.transactionId,
      input.productId,
      new Date().toISOString(),
      input.platform,
      input.eventId,
    )
    .run();
}

async function markPurchaseEvent(
  env: StoreNotificationEnv,
  platform: string,
  eventId: string,
  status: string,
  errorCode: string | null = null,
  errorMessage: string | null = null,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE purchase_events
     SET status = ?, processed_at = ?, error_code = ?, error_message = ?,
         updated_at = ?
     WHERE platform = ? AND event_id = ?`,
  )
    .bind(status, now, errorCode, errorMessage, now, platform, eventId)
    .run();
}

function googleEventType(notification: Record<string, unknown>): string {
  if (notification.voidedPurchaseNotification) return 'voided_purchase';
  const oneTime = asObject(notification.oneTimeProductNotification);
  if (oneTime) {
    return numberValue(oneTime.notificationType) === 1
      ? 'one_time_product_purchased'
      : 'one_time_product_cancelled';
  }
  if (notification.testNotification) return 'test';
  return 'unsupported';
}

function googlePurchaseToken(
  notification: Record<string, unknown>,
): string | null {
  const source =
    asObject(notification.voidedPurchaseNotification) ??
    asObject(notification.oneTimeProductNotification);
  return stringValue(source?.purchaseToken);
}

function googleProductId(
  notification: Record<string, unknown>,
): string | null {
  return stringValue(
    asObject(notification.oneTimeProductNotification)?.sku,
  );
}

function parseBase64Json(value: string): Record<string, unknown> {
  try {
    const decoded = atob(value.replace(/-/g, '+').replace(/_/g, '/'));
    const parsed = JSON.parse(decoded);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error();
    }
    return parsed as Record<string, unknown>;
  } catch {
    throw new StoreNotificationError(
      400,
      'The Pub/Sub notification data is invalid.',
      'invalid_pubsub_data',
    );
  }
}

async function parseJsonObject(
  request: Request,
): Promise<Record<string, unknown>> {
  try {
    const parsed = await request.json();
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error();
    }
    return parsed as Record<string, unknown>;
  } catch {
    throw new StoreNotificationError(400, 'Invalid JSON body.', 'invalid_json');
  }
}

function assertProduction(env: StoreNotificationEnv): void {
  if ((env.ENVIRONMENT ?? '').toLowerCase() !== 'production') {
    throw new StoreNotificationError(
      400,
      'Store notifications are accepted only in production.',
      'invalid_environment',
    );
  }
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function requiredString(value: unknown, field: string): string {
  const result = stringValue(value);
  if (!result) {
    throw new StoreNotificationError(
      400,
      `${field} is required.`,
      'invalid_request',
    );
  }
  return result;
}

function numberValue(value: unknown): number | null {
  const result = Number(value);
  return Number.isFinite(result) ? result : null;
}

function requiredEnv(value: string | undefined, message: string): string {
  const result = value?.trim();
  if (!result || result.startsWith('REPLACE_')) {
    throw new StoreNotificationError(
      503,
      message,
      'store_notifications_unavailable',
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
