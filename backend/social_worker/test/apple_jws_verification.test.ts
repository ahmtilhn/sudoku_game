import { describe, expect, it } from 'vitest';

import {
  AppleJwsVerificationError,
  verifyAppleStoreKitJws,
} from '../src/apple_jws_verifier';

function encodeJson(value: unknown): string {
  return btoa(JSON.stringify(value))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

describe('Apple StoreKit JWS verification', () => {
  it('rejects values that are not compact JWS', async () => {
    await expect(
      verifyAppleStoreKitJws('not-a-jws', {
        trustedRootCertificatesPem: 'unused',
        expectedBundleId: 'com.devoviastudio.sudoku',
      }),
    ).rejects.toMatchObject<Partial<AppleJwsVerificationError>>({
      code: 'invalid_apple_signature',
    });
  });

  it('rejects unsupported signing algorithms before payload trust', async () => {
    const value = [
      encodeJson({ alg: 'none', x5c: ['fake', 'fake'] }),
      encodeJson({ bundleId: 'com.devoviastudio.sudoku' }),
      'signature',
    ].join('.');

    await expect(
      verifyAppleStoreKitJws(value, {
        trustedRootCertificatesPem: 'unused',
        expectedBundleId: 'com.devoviastudio.sudoku',
      }),
    ).rejects.toThrow('does not use ES256');
  });

  it('rejects ES256 JWS without an Apple certificate chain', async () => {
    const value = [
      encodeJson({ alg: 'ES256' }),
      encodeJson({ bundleId: 'com.devoviastudio.sudoku' }),
      encodeJson('signature'),
    ].join('.');

    await expect(
      verifyAppleStoreKitJws(value, {
        trustedRootCertificatesPem: 'unused',
        expectedBundleId: 'com.devoviastudio.sudoku',
      }),
    ).rejects.toThrow('certificate chain is missing');
  });
});
