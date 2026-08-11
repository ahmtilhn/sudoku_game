import { SignJWT, importPKCS8 } from 'jose';

export type AppleStoreApiEnv = {
  APPLE_IAP_ISSUER_ID?: string;
  APPLE_IAP_KEY_ID?: string;
  APPLE_IAP_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID?: string;
};

export async function appStoreApiToken(
  env: AppleStoreApiEnv,
): Promise<string> {
  const bundleId = requireCredential(
    env.APPLE_BUNDLE_ID,
    'Apple bundle ID is not configured.',
  );
  const issuerId = requireCredential(
    env.APPLE_IAP_ISSUER_ID,
    'Apple In-App Purchase issuer ID is not configured.',
  );
  const keyId = requireCredential(
    env.APPLE_IAP_KEY_ID,
    'Apple In-App Purchase key ID is not configured.',
  );
  const privateKey = requireCredential(
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

function requireCredential(value: string | undefined, message: string): string {
  const result = value?.trim();
  if (!result || result.startsWith('REPLACE_')) throw new Error(message);
  return result;
}
