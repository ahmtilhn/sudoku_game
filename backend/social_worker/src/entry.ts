import app, { GameRoom, MatchmakingQueue } from './profile_wrapper';
import type { Env } from './index';
import { AppCheckError } from './app_check';
import {
  AccountDeletionError,
  deletePlayerAccountData,
  isAccountDeletionPath,
} from './account_deletion';
import {
  AccountProtectionError,
  assertProtectedPurchaseAccount,
  isPurchaseVerificationPath,
} from './account_protection_gate';
import { runRetentionCleanup } from './cost_retention';
import {
  AdMobSsvError,
  assertProductionRewardConfirmedBySsv,
  handleAdMobSsv,
  isAdMobSsvPath,
} from './admob_ssv';
import {
  ProductionVerificationError,
  isProductionPurchasePath,
  reconcilePendingGooglePurchases,
  verifyAndGrantProductionPurchase,
} from './production_purchase_verification_v2';
import { sendPlayerPush } from './push_notifications';
import { ensureRuntimeSchema } from './runtime_schema';
import { ensureTestEconomySchema } from './test_economy_schema';
import {
  StoreNotificationError,
  handleAppleServerNotification,
  handleGooglePlayRtdn,
  isAppleServerNotificationPath,
  isGooglePlayRtdnPath,
} from './store_notifications';
import { runStoreReconciliation } from './store_reconciliation';

export { GameRoom, MatchmakingQueue };

type RuntimeEnv = Env & {
  ALLOW_TEST_PURCHASE_GRANTS?: string;
  TEST_STARTER_COINS?: string;
  GOOGLE_PLAY_CLIENT_EMAIL?: string;
  GOOGLE_PLAY_PRIVATE_KEY?: string;
  GOOGLE_PLAY_PACKAGE_NAME?: string;
  GOOGLE_PUBSUB_AUDIENCE?: string;
  GOOGLE_PUBSUB_SERVICE_ACCOUNT?: string;
  APPLE_IAP_ISSUER_ID?: string;
  APPLE_IAP_KEY_ID?: string;
  APPLE_IAP_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID?: string;
  APPLE_ROOT_CERTIFICATES_PEM?: string;
  ADMOB_REWARDED_AD_UNITS?: string;
};

export default {
  async fetch(
    request: Request,
    env: RuntimeEnv,
    ctx: ExecutionContext,
  ): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(env),
      });
    }

    try {
      await ensureRuntimeSchema(env);
      await ensureTestEconomySchema(env);
    } catch (error) {
      console.error('runtime_schema_install_failed', error);
      return json(env, 503, {
        error: 'The database schema is not ready.',
        code: 'runtime_schema_install_failed',
      });
    }

    const url = new URL(request.url);
    try {
      if (isGooglePlayRtdnPath(url.pathname)) {
        return withCors(await handleGooglePlayRtdn(request, env), env);
      }

      if (isAppleServerNotificationPath(url.pathname)) {
        return withCors(await handleAppleServerNotification(request, env), env);
      }

      if (isAdMobSsvPath(url.pathname)) {
        return withCors(await handleAdMobSsv(request, env), env);
      }

      if (isAccountDeletionPath(url.pathname)) {
        return json(env, 200, await deletePlayerAccountData(request, env));
      }

      if (isPurchaseVerificationPath(url.pathname)) {
        await assertProtectedPurchaseAccount(request, env);
      }

      if (
        (env.ENVIRONMENT ?? '').toLowerCase() === 'production' &&
        isProductionPurchasePath(url.pathname)
      ) {
        const verification = await verifyAndGrantProductionPurchase(request, env);
        const walletRequest = new Request(
          new URL('/v1/me/wallet', request.url),
          {
            method: 'GET',
            headers: request.headers,
          },
        );
        const walletResponse = await app.fetch(walletRequest, env, ctx);
        if (!walletResponse.ok) return withCors(walletResponse, env);
        const wallet = (await walletResponse.json()) as Record<string, unknown>;
        return json(env, 200, {
          ...wallet,
          purchaseGranted: verification.granted,
          androidConsumptionHandledByServer: verification.consumed === true,
          androidAcknowledgementHandledByServer:
            verification.acknowledged === true,
        });
      }

      if (isProductionRewardConfirmation(request, env, url)) {
        await assertProductionRewardConfirmedBySsv(request, env);
      }
    } catch (error) {
      return verificationErrorResponse(error, env);
    }

    const routedRequest = await protectProfileDisplayName(request, url);
    const response = await app.fetch(routedRequest, env, ctx);
    if (response.status === 101) return response;

    if (
      response.status === 201 &&
      request.method === 'POST' &&
      /^\/v1\/matches\/[^/]+\/rematch$/.test(url.pathname)
    ) {
      ctx.waitUntil(notifyRematchRecipient(env, response.clone()));
    }

    return withCors(response, env);
  },

  async scheduled(
    event: ScheduledEvent,
    env: RuntimeEnv,
    ctx: ExecutionContext,
  ): Promise<void> {
    void event;
    try {
      await ensureRuntimeSchema(env);
      await ensureTestEconomySchema(env);
    } catch (error) {
      console.error('runtime_schema_install_failed', error);
      return;
    }

    ctx.waitUntil(
      runRetentionCleanup(env)
        .then((results) => {
          console.log('retention_cleanup_completed', { results });
        })
        .catch((error: unknown) => {
          console.error('retention_cleanup_failed', {
            message: error instanceof Error ? error.message : 'unknown',
          });
        }),
    );

    if ((env.ENVIRONMENT ?? '').toLowerCase() === 'production') {
      ctx.waitUntil(
        reconcilePendingGooglePurchases(env)
          .then((result) => {
            console.log('purchase_lifecycle_reconciliation_completed', result);
          })
          .catch((error: unknown) => {
            console.error('purchase_lifecycle_reconciliation_failed', {
              message: error instanceof Error ? error.message : 'unknown',
            });
          }),
      );
      ctx.waitUntil(
        runStoreReconciliation(env)
          .then((results) => {
            console.log('store_refund_reconciliation_completed', { results });
          })
          .catch((error: unknown) => {
            console.error('store_refund_reconciliation_failed', {
              message: error instanceof Error ? error.message : 'unknown',
            });
          }),
      );
    }
  },
};

function isProductionRewardConfirmation(
  request: Request,
  env: RuntimeEnv,
  url: URL,
): boolean {
  if ((env.ENVIRONMENT ?? '').toLowerCase() !== 'production') return false;
  if (request.method !== 'POST') return false;
  return (
    url.pathname === '/v1/rewards/daily-ad/confirm' ||
    url.pathname === '/v1/rewards/career-ad/confirm'
  );
}

async function protectProfileDisplayName(
  request: Request,
  url: URL,
): Promise<Request> {
  if (request.method !== 'POST' || url.pathname !== '/v1/me') return request;
  try {
    const body = (await request.clone().json()) as Record<string, unknown>;
    if (!body || typeof body !== 'object' || Array.isArray(body)) return request;
    const sanitized = { ...body };
    delete sanitized.displayName;
    const headers = new Headers(request.headers);
    headers.set('content-type', 'application/json');
    return new Request(request.url, {
      method: request.method,
      headers,
      body: JSON.stringify(sanitized),
    });
  } catch {
    return request;
  }
}

async function notifyRematchRecipient(
  env: RuntimeEnv,
  response: Response,
): Promise<void> {
  try {
    const body = (await response.json()) as Record<string, unknown>;
    const invitationId = String(body.id ?? '');
    const previousMatchId = String(body.previousMatchId ?? '');
    const recipient = asObject(body.recipient);
    const sender = asObject(body.sender);
    const recipientPublicId = String(recipient?.publicId ?? '');
    const senderName = String(sender?.displayName ?? 'A player');
    if (!invitationId || !recipientPublicId) return;

    const player = await env.DB.prepare(
      'SELECT id FROM players WHERE public_id = ? LIMIT 1',
    )
      .bind(recipientPublicId)
      .first<{ id: string }>();
    if (!player) return;

    await sendPlayerPush(env, player.id, {
      title: 'Rematch invitation',
      body: `${senderName} wants to play again. You have 10 seconds to respond.`,
      tag: `rematch_${invitationId}`,
      data: {
        type: 'rematch_invitation',
        rematchId: invitationId,
        previousMatchId,
      },
    });
  } catch (error) {
    console.error('Rematch push failed', error);
  }
}

function verificationErrorResponse(
  error: unknown,
  env: RuntimeEnv,
): Response {
  if (error instanceof AppCheckError) {
    return json(env, 403, { error: error.code, code: error.code });
  }
  if (
    error instanceof ProductionVerificationError ||
    error instanceof AdMobSsvError ||
    error instanceof AccountProtectionError ||
    error instanceof AccountDeletionError ||
    error instanceof StoreNotificationError
  ) {
    return json(env, error.status, { error: error.message, code: error.code });
  }
  console.error('Production verification route failed', error);
  return json(env, 500, {
    error: 'Production verification failed.',
    code: 'production_verification_failed',
  });
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function withCors(response: Response, env: RuntimeEnv): Response {
  if (response.status === 101) return response;
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders(env))) {
    if (!headers.has(key)) headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function json(env: RuntimeEnv, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...corsHeaders(env),
    },
  });
}

function corsHeaders(env: RuntimeEnv): Record<string, string> {
  return {
    'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
    'access-control-allow-headers':
      'authorization, content-type, x-firebase-appcheck',
    'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
  };
}
