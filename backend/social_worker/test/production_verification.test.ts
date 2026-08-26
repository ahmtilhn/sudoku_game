import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { handleAdMobSsv, isAdMobSsvPath } from '../src/admob_ssv';
import {
  ProductionVerificationError,
  isProductionPurchasePath,
  verifyAndGrantProductionPurchase,
} from '../src/production_purchase_verification_v2';

describe('production purchase verification routing', () => {
  it('recognizes only the supported Google Play and App Store routes', () => {
    expect(isProductionPurchasePath('/v1/purchases/google/verify')).toBe(true);
    expect(isProductionPurchasePath('/v1/purchases/apple/verify')).toBe(true);
    expect(isProductionPurchasePath('/v1/purchases/unknown/verify')).toBe(false);
    expect(isProductionPurchasePath('/v1/me/wallet')).toBe(false);
  });

  it('refuses to run the production verifier outside production', async () => {
    const request = new Request('https://example.test/v1/purchases/google/verify', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        productId: 'coins_100',
        transactionId: 'transaction-1',
        verificationData: 'purchase-token-1',
      }),
    });

    await expect(
      verifyAndGrantProductionPurchase(request, {
        DB: {} as D1Database,
        FIREBASE_PROJECT_ID: 'project-id',
        ENVIRONMENT: 'staging',
      }),
    ).rejects.toMatchObject<Partial<ProductionVerificationError>>({
      status: 400,
      code: 'invalid_environment',
    });
  });

  it('rejects unsupported HTTP methods before authentication', async () => {
    const request = new Request('https://example.test/v1/purchases/google/verify', {
      method: 'GET',
    });

    await expect(
      verifyAndGrantProductionPurchase(request, {
        DB: {} as D1Database,
        FIREBASE_PROJECT_ID: 'project-id',
        ENVIRONMENT: 'production',
      }),
    ).rejects.toMatchObject<Partial<ProductionVerificationError>>({
      status: 405,
      code: 'method_not_allowed',
    });
  });

  it('does not put the old protected-account gate before store verification', () => {
    const source = readFileSync('src/entry.ts', 'utf8');

    expect(source).not.toContain('assertProtectedPurchaseAccount(request, env)');
    expect(source).toContain('verifyAndGrantProductionPurchase(request, env)');
  });

  it('returns a wallet-shaped purchase response with lifecycle flags', () => {
    const source = readFileSync('src/entry.ts', 'utf8');

    expect(source).toContain("new URL('/v1/me/wallet', request.url)");
    expect(source).toContain('purchaseGranted: verification.granted');
    expect(source).toContain(
      'androidConsumptionHandledByServer: verification.consumed === true',
    );
    expect(source).toContain(
      'androidAcknowledgementHandledByServer:',
    );
  });

  it('treats duplicate transaction insert races as idempotent replay', () => {
    const source = readFileSync(
      'src/production_purchase_verification_v2.ts',
      'utf8',
    );

    expect(source).toContain('isPurchaseUniqueConstraintError(error)');
    expect(source).toContain('existing?.player_id === playerId');
    expect(source).toContain('return false;');
    expect(source).toContain('purchase_replayed');
  });

  it('keeps App Store receipt fallback compatible with server verification', () => {
    const source = readFileSync(
      'src/production_purchase_verification_v2.ts',
      'utf8',
    );

    expect(source).toContain('tryDecodeUntrustedStoreKitJws(input.verificationData)');
    expect(source).toContain(
      'stringOrNull(clientPayload?.transactionId) ?? input.transactionId',
    );
    expect(source).toContain('inApps/v1/transactions/');
    expect(source).toContain('verificationData: signedTransactionInfo');
    expect(source).toContain('verifyAppStoreReceiptFallback');
    expect(source).toContain('https://buy.itunes.apple.com/verifyReceipt');
    expect(source).toContain('https://sandbox.itunes.apple.com/verifyReceipt');
    expect(source).toContain("verificationSource: 'app_store_verify_receipt'");
    expect(source).toContain('receipt.in_app');
    expect(source).toContain('receiptTransactionMatches');
    expect(source).toContain('128_000');
    expect(source).not.toContain(
      'The client transaction is not a valid StoreKit 2 signed transaction.',
    );
  });
});

describe('AdMob SSV routing', () => {
  it('recognizes only the public SSV callback path', () => {
    expect(isAdMobSsvPath('/v1/rewards/admob/ssv')).toBe(true);
    expect(isAdMobSsvPath('/v1/rewards/daily-ad/confirm')).toBe(false);
  });

  it('rejects non-GET callbacks before reading any database state', async () => {
    const response = await handleAdMobSsv(
      new Request('https://example.test/v1/rewards/admob/ssv', {
        method: 'POST',
      }),
      {
        DB: {} as D1Database,
        FIREBASE_PROJECT_ID: 'project-id',
        ENVIRONMENT: 'production',
      },
    );
    expect(response.status).toBe(405);
    await expect(response.json()).resolves.toMatchObject({
      code: 'method_not_allowed',
    });
  });
});
