import { createRemoteJWKSet, jwtVerify } from 'jose';

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

export type AccountProtectionEnv = {
  FIREBASE_PROJECT_ID: string;
};

export class AccountProtectionError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

export function isPurchaseVerificationPath(pathname: string): boolean {
  return (
    pathname === '/v1/purchases/google/verify' ||
    pathname === '/v1/purchases/apple/verify'
  );
}

export async function assertProtectedPurchaseAccount(
  request: Request,
  env: AccountProtectionEnv,
): Promise<void> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) {
    throw new AccountProtectionError(401, 'Missing bearer token.', 'missing_token');
  }
  const token = header.slice(7).trim();
  if (!token) {
    throw new AccountProtectionError(401, 'Missing bearer token.', 'missing_token');
  }

  const issuer = `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`;
  let payload: Record<string, unknown>;
  try {
    const verified = await jwtVerify(token, FIREBASE_JWKS, {
      algorithms: ['RS256'],
      issuer,
      audience: env.FIREBASE_PROJECT_ID,
    });
    payload = verified.payload as Record<string, unknown>;
  } catch {
    throw new AccountProtectionError(
      401,
      'Invalid or expired player token.',
      'invalid_token',
    );
  }

  const firebase =
    payload.firebase && typeof payload.firebase === 'object'
      ? (payload.firebase as Record<string, unknown>)
      : null;
  const provider = firebase?.sign_in_provider;
  if (provider === 'anonymous' || typeof provider !== 'string') {
    throw new AccountProtectionError(
      409,
      'Protect or sign in to your player account before buying Coins.',
      'account_protection_required',
    );
  }

  if (provider === 'password' && payload.email_verified !== true) {
    throw new AccountProtectionError(
      409,
      'Verify your email address before buying Coins.',
      'email_verification_required',
    );
  }
}
