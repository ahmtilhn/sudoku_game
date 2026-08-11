import { decodeProtectedHeader, jwtVerify, type JWTPayload } from 'jose';

export type AppCheckEnv = {
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
};

export type AppCheckVerifier = (
  token: string,
  env: AppCheckEnv,
) => Promise<JWTPayload>;

const APP_CHECK_JWKS_URL = 'https://firebaseappcheck.googleapis.com/v1/jwks';
let cachedVerifier: AppCheckVerifier | null = null;

export class AppCheckError extends Error {
  constructor(
    readonly code: string,
    message = 'App Check verification failed.',
  ) {
    super(message);
  }
}

export async function verifyAppCheckRequest(
  request: Request,
  env: AppCheckEnv,
  verifier: AppCheckVerifier = defaultAppCheckVerifier,
): Promise<JWTPayload | null> {
  const required = env.REQUIRE_APP_CHECK === 'true';
  const token = request.headers.get('x-firebase-appcheck')?.trim();
  if (!token) {
    if (required) throw new AppCheckError('app_check_required');
    return null;
  }

  try {
    return await verifier(token, env);
  } catch (error) {
    console.warn('App Check rejected', {
      code: error instanceof AppCheckError ? error.code : 'invalid_app_check',
    });
    if (required) {
      throw error instanceof AppCheckError
        ? error
        : new AppCheckError('invalid_app_check');
    }
    return null;
  }
}

export async function defaultAppCheckVerifier(
  token: string,
  env: AppCheckEnv,
): Promise<JWTPayload> {
  const projectNumber = requiredConfig(env.FIREBASE_PROJECT_NUMBER, 'FIREBASE_PROJECT_NUMBER');
  const allowedApps = allowedAppIds(env);
  const header = decodeProtectedHeader(token);
  if (header.alg !== 'RS256') throw new AppCheckError('invalid_alg');
  if (header.typ !== undefined && header.typ !== 'JWT') {
    throw new AppCheckError('invalid_typ');
  }
  const verifier =
    cachedVerifier ??
    (cachedVerifier = remoteJwksVerifier(new URL(APP_CHECK_JWKS_URL)));
  return verifier(token, { ...env, FIREBASE_PROJECT_NUMBER: projectNumber, ALLOWED_APP_CHECK_APP_IDS: allowedApps.join(',') });
}

type VerificationKey = Parameters<typeof jwtVerify>[1];

export function createStaticAppCheckVerifier(key: VerificationKey): AppCheckVerifier {
  return async (token, env) => verifyWithKey(token, env, key);
}

function remoteJwksVerifier(url: URL): AppCheckVerifier {
  return async (token, env) => {
    const { createRemoteJWKSet } = await import('jose');
    const jwks = createRemoteJWKSet(url, { cooldownDuration: 300_000 });
    return verifyWithKey(token, env, jwks);
  };
}

async function verifyWithKey(
  token: string,
  env: AppCheckEnv,
  key: VerificationKey,
): Promise<JWTPayload> {
  const projectNumber = requiredConfig(env.FIREBASE_PROJECT_NUMBER, 'FIREBASE_PROJECT_NUMBER');
  const allowedApps = allowedAppIds(env);
  const verified = await jwtVerify(token, key, {
    algorithms: ['RS256'],
    issuer: `https://firebaseappcheck.googleapis.com/${projectNumber}`,
    audience: `projects/${projectNumber}`,
  });
  const appId = verified.payload.sub;
  if (!appId || !allowedApps.includes(appId)) {
    throw new AppCheckError('app_id_not_allowed');
  }
  return verified.payload;
}

function allowedAppIds(env: AppCheckEnv): string[] {
  return requiredConfig(env.ALLOWED_APP_CHECK_APP_IDS, 'ALLOWED_APP_CHECK_APP_IDS')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

function requiredConfig(value: string | undefined, name: string): string {
  if (!value || value.startsWith('REPLACE_')) {
    throw new AppCheckError(`${name.toLowerCase()}_missing`);
  }
  return value;
}
