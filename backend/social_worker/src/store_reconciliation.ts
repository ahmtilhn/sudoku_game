import { verifyAppleStoreKitJws } from './apple_jws_verifier';
import { appStoreApiToken } from './apple_store_api';
import { googlePlayAccessToken } from './google_play_lifecycle';
import type { StoreNotificationEnv } from './store_notifications';
import { applyPurchaseRevocation } from './store_notifications';

type CursorRow = {
  cursor_value: string;
};

type ApplePurchaseRow = {
  transaction_id: string;
  store_order_id: string | null;
  store_environment: string | null;
};

type ReconciliationResult = {
  platform: 'android' | 'ios';
  scanned: number;
  changed: number;
  errors: number;
};

export async function runStoreReconciliation(
  env: StoreNotificationEnv,
): Promise<ReconciliationResult[]> {
  if ((env.ENVIRONMENT ?? '').toLowerCase() !== 'production') return [];
  const results: ReconciliationResult[] = [];
  results.push(await reconcileGoogleVoidedPurchases(env));
  results.push(await reconcileAppleRefunds(env));
  return results;
}

export async function reconcileGoogleVoidedPurchases(
  env: StoreNotificationEnv,
): Promise<ReconciliationResult> {
  const result: ReconciliationResult = {
    platform: 'android',
    scanned: 0,
    changed: 0,
    errors: 0,
  };
  const runId = await startRun(env, 'android', 'voided_purchases');
  try {
    const packageName = required(
      env.GOOGLE_PLAY_PACKAGE_NAME,
      'Google Play package name is not configured.',
    );
    const now = Date.now();
    const cursor = await readCursor(env, 'android', 'voided_start_time');
    const oldestAllowed = now - 29 * 24 * 60 * 60 * 1000;
    const previous = Number(cursor);
    const startTime = Number.isFinite(previous)
      ? Math.max(oldestAllowed, previous - 5 * 60 * 1000)
      : oldestAllowed;

    let pageToken: string | null = null;
    let page = 0;
    do {
      const url = new URL(
        'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/' +
          `${encodeURIComponent(packageName)}/purchases/voidedpurchases`,
      );
      url.searchParams.set('startTime', Math.trunc(startTime).toString());
      url.searchParams.set('endTime', Math.trunc(now).toString());
      url.searchParams.set('type', '1');
      url.searchParams.set('includeQuantityBasedPartialRefund', 'true');
      url.searchParams.set('pageSelection.maxResults', '1000');
      if (pageToken) url.searchParams.set('pageSelection.token', pageToken);

      let response = await fetch(url, {
        headers: {
          authorization: `Bearer ${await googlePlayAccessToken(env)}`,
          accept: 'application/json',
        },
      });
      if (response.status === 401) {
        response = await fetch(url, {
          headers: {
            authorization: `Bearer ${await googlePlayAccessToken(env, true)}`,
            accept: 'application/json',
          },
        });
      }
      if (!response.ok) {
        throw new Error(
          `Google Voided Purchases API failed (${response.status}): ${await safeText(response)}`,
        );
      }

      const body = (await response.json()) as Record<string, unknown>;
      const purchases = Array.isArray(body.voidedPurchases)
        ? body.voidedPurchases
        : [];
      for (const raw of purchases) {
        const purchase = objectValue(raw);
        if (!purchase) continue;
        const purchaseToken = stringValue(purchase.purchaseToken);
        if (!purchaseToken) continue;
        result.scanned++;
        try {
          const changed = await applyPurchaseRevocation(env, {
            platform: 'android',
            transactionId: purchaseToken,
            storeOrderId: stringValue(purchase.orderId),
            source: 'google_play_voided_api',
            sourceEventId:
              `voided:${stringValue(purchase.orderId) ?? purchaseToken}:` +
              `${stringValue(purchase.voidedTimeMillis) ?? 'unknown'}`,
          });
          if (changed) result.changed++;
        } catch (error) {
          result.errors++;
          console.error('google_voided_purchase_reconcile_failed', {
            purchaseToken,
            message: errorMessage(error),
          });
        }
      }

      const pagination = objectValue(body.tokenPagination);
      pageToken = stringValue(pagination?.nextPageToken);
      page++;
    } while (pageToken && page < 10);

    await writeCursor(
      env,
      'android',
      'voided_start_time',
      Math.trunc(now).toString(),
    );
    await completeRun(env, runId, result);
    return result;
  } catch (error) {
    result.errors++;
    await failRun(env, runId, result, error);
    throw error;
  }
}

export async function reconcileAppleRefunds(
  env: StoreNotificationEnv,
): Promise<ReconciliationResult> {
  const result: ReconciliationResult = {
    platform: 'ios',
    scanned: 0,
    changed: 0,
    errors: 0,
  };
  const runId = await startRun(env, 'ios', 'refund_history');
  try {
    const bundleId = required(
      env.APPLE_BUNDLE_ID,
      'Apple bundle ID is not configured.',
    );
    const roots = required(
      env.APPLE_ROOT_CERTIFICATES_PEM,
      'Trusted Apple root certificates are not configured.',
    );
    const apiToken = await appStoreApiToken(env);
    const rows = await env.DB.prepare(
      `SELECT transaction_id, store_order_id, store_environment
       FROM purchase_grants
       WHERE platform = 'ios'
         AND status <> 'revoked'
       ORDER BY updated_at ASC
       LIMIT 50`,
    ).all<ApplePurchaseRow>();

    for (const row of rows.results ?? []) {
      const environment = row.store_environment === 'sandbox'
        ? 'sandbox'
        : 'production';
      const host = environment === 'sandbox'
        ? 'https://api.storekit-sandbox.apple.com'
        : 'https://api.storekit.apple.com';
      const lookupId = row.store_order_id || row.transaction_id;
      let revision: string | null = null;
      let page = 0;
      try {
        do {
          const url = new URL(
            `${host}/inApps/v2/refund/lookup/${encodeURIComponent(lookupId)}`,
          );
          if (revision) url.searchParams.set('revision', revision);
          const response = await fetch(url, {
            headers: {
              authorization: `Bearer ${apiToken}`,
              accept: 'application/json',
            },
          });
          if (response.status === 404) break;
          if (!response.ok) {
            throw new Error(
              `App Store refund history failed (${response.status}): ${await safeText(response)}`,
            );
          }
          const body = (await response.json()) as Record<string, unknown>;
          const signedTransactions = Array.isArray(body.signedTransactions)
            ? body.signedTransactions.filter(
                (item): item is string => typeof item === 'string',
              )
            : [];
          for (const signedTransaction of signedTransactions) {
            result.scanned++;
            try {
              const transaction = await verifyAppleStoreKitJws(
                signedTransaction,
                {
                  trustedRootCertificatesPem: roots,
                  expectedBundleId: bundleId,
                  expectedEnvironment: environment,
                },
              );
              if (
                transaction.revocationDate == null &&
                transaction.revocationReason == null
              ) {
                continue;
              }
              const transactionId = stringValue(transaction.transactionId);
              if (!transactionId) continue;
              const changed = await applyPurchaseRevocation(env, {
                platform: 'ios',
                transactionId,
                storeOrderId: stringValue(transaction.originalTransactionId),
                source: 'app_store_refund_history',
                sourceEventId:
                  `refund-history:${transactionId}:` +
                  `${String(transaction.revocationDate ?? 'unknown')}`,
              });
              if (changed) result.changed++;
            } catch (error) {
              result.errors++;
              console.error('apple_refund_transaction_reconcile_failed', {
                lookupId,
                message: errorMessage(error),
              });
            }
          }
          revision = body.hasMore === true
            ? stringValue(body.revision)
            : null;
          page++;
        } while (revision && page < 10);
      } catch (error) {
        result.errors++;
        console.error('apple_refund_history_reconcile_failed', {
          lookupId,
          message: errorMessage(error),
        });
      }
    }

    await completeRun(env, runId, result);
    return result;
  } catch (error) {
    result.errors++;
    await failRun(env, runId, result, error);
    throw error;
  }
}

async function startRun(
  env: StoreNotificationEnv,
  platform: string,
  kind: string,
): Promise<string> {
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO reconciliation_runs (
       id, platform, kind, status, started_at, updated_at
     ) VALUES (?, ?, ?, 'running', ?, ?)`,
  )
    .bind(id, platform, kind, now, now)
    .run();
  return id;
}

async function completeRun(
  env: StoreNotificationEnv,
  runId: string,
  result: ReconciliationResult,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE reconciliation_runs
     SET status = 'completed', scanned_count = ?, changed_count = ?,
         error_count = ?, completed_at = ?, updated_at = ?
     WHERE id = ?`,
  )
    .bind(
      result.scanned,
      result.changed,
      result.errors,
      now,
      now,
      runId,
    )
    .run();
}

async function failRun(
  env: StoreNotificationEnv,
  runId: string,
  result: ReconciliationResult,
  error: unknown,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE reconciliation_runs
     SET status = 'failed', scanned_count = ?, changed_count = ?,
         error_count = ?, metadata_json = ?, completed_at = ?, updated_at = ?
     WHERE id = ?`,
  )
    .bind(
      result.scanned,
      result.changed,
      result.errors,
      JSON.stringify({ error: errorMessage(error) }),
      now,
      now,
      runId,
    )
    .run();
}

async function readCursor(
  env: StoreNotificationEnv,
  platform: string,
  key: string,
): Promise<string | null> {
  const row = await env.DB.prepare(
    `SELECT cursor_value FROM store_notification_cursors
     WHERE platform = ? AND cursor_key = ? LIMIT 1`,
  )
    .bind(platform, key)
    .first<CursorRow>();
  return row?.cursor_value ?? null;
}

async function writeCursor(
  env: StoreNotificationEnv,
  platform: string,
  key: string,
  value: string,
): Promise<void> {
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO store_notification_cursors (
       platform, cursor_key, cursor_value, updated_at
     ) VALUES (?, ?, ?, ?)
     ON CONFLICT(platform, cursor_key) DO UPDATE SET
       cursor_value = excluded.cursor_value,
       updated_at = excluded.updated_at`,
  )
    .bind(platform, key, value, now)
    .run();
}

function required(value: string | undefined, message: string): string {
  const result = value?.trim();
  if (!result || result.startsWith('REPLACE_')) throw new Error(message);
  return result;
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

async function safeText(response: Response): Promise<string> {
  try {
    const value = (await response.text()).trim();
    return value.length > 500 ? value.slice(0, 500) : value;
  } catch {
    return '';
  }
}

function errorMessage(error: unknown): string {
  const value = error instanceof Error ? error.message : String(error);
  return value.length > 500 ? value.slice(0, 500) : value;
}
