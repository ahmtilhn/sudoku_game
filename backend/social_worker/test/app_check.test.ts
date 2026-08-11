import { SignJWT, generateKeyPair } from 'jose';
import { describe, expect, it, vi } from 'vitest';

import {
  AppCheckError,
  createStaticAppCheckVerifier,
  verifyAppCheckRequest,
} from '../src/app_check';

const env = {
  FIREBASE_PROJECT_NUMBER: '31445697560',
  ALLOWED_APP_CHECK_APP_IDS: '1:31445697560:android:abc,1:31445697560:ios:def',
};

describe('Firebase App Check verifier', () => {
  it('allows missing token when enforcement is false', async () => {
    await expect(
      verifyAppCheckRequest(new Request('https://test.local'), {
        ...env,
        REQUIRE_APP_CHECK: 'false',
      }),
    ).resolves.toBeNull();
  });

  it('rejects missing token when enforcement is true', async () => {
    await expect(
      verifyAppCheckRequest(new Request('https://test.local'), {
        ...env,
        REQUIRE_APP_CHECK: 'true',
      }),
    ).rejects.toMatchObject({ code: 'app_check_required' });
  });

  it('accepts valid Android and iOS app tokens', async () => {
    const { privateKey, publicKey } = await generateKeyPair('RS256');
    const verifier = createStaticAppCheckVerifier(publicKey);
    for (const appId of ['1:31445697560:android:abc', '1:31445697560:ios:def']) {
      const token = await appCheckToken(privateKey, appId);
      const payload = await verifyAppCheckRequest(
        new Request('https://test.local', {
          headers: { 'x-firebase-appcheck': token },
        }),
        { ...env, REQUIRE_APP_CHECK: 'true' },
        verifier,
      );
      expect(payload?.sub).toBe(appId);
    }
  });

  it('rejects wrong issuer, audience, expiry, and app ID', async () => {
    const { privateKey, publicKey } = await generateKeyPair('RS256');
    const verifier = createStaticAppCheckVerifier(publicKey);
    await expectToken(privateKey, verifier, { issuer: 'https://wrong' });
    await expectToken(privateKey, verifier, { audience: 'projects/wrong' });
    await expectToken(privateKey, verifier, { expiresIn: -1 });
    await expectToken(privateKey, verifier, { subject: 'not-allowed' });
  });

  it('does not log token contents on invalid optional token', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const token = 'header.payload.signature';
    await verifyAppCheckRequest(
      new Request('https://test.local', {
        headers: { 'x-firebase-appcheck': token },
      }),
      { ...env, REQUIRE_APP_CHECK: 'false' },
      async () => {
        throw new AppCheckError('invalid_signature');
      },
    );
    expect(JSON.stringify(warn.mock.calls)).not.toContain(token);
    warn.mockRestore();
  });
});

async function expectToken(
  privateKey: CryptoKey,
  verifier: ReturnType<typeof createStaticAppCheckVerifier>,
  override: {
    issuer?: string;
    audience?: string;
    subject?: string;
    expiresIn?: number;
  },
) {
  const token = await appCheckToken(
    privateKey,
    override.subject ?? '1:31445697560:android:abc',
    override,
  );
  await expect(
    verifyAppCheckRequest(
      new Request('https://test.local', {
        headers: { 'x-firebase-appcheck': token },
      }),
      { ...env, REQUIRE_APP_CHECK: 'true' },
      verifier,
    ),
  ).rejects.toBeTruthy();
}

async function appCheckToken(
  privateKey: CryptoKey,
  subject: string,
  override: {
    issuer?: string;
    audience?: string;
    expiresIn?: number;
  } = {},
): Promise<string> {
  return new SignJWT({ sub: subject })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(
      override.issuer ??
        `https://firebaseappcheck.googleapis.com/${env.FIREBASE_PROJECT_NUMBER}`,
    )
    .setAudience(override.audience ?? `projects/${env.FIREBASE_PROJECT_NUMBER}`)
    .setIssuedAt()
    .setExpirationTime(`${override.expiresIn ?? 3600}s`)
    .sign(privateKey);
}
