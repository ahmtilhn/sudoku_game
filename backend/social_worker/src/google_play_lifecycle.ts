import { SignJWT, importPKCS8 } from 'jose';

export type GooglePlayLifecycleEnv = {
  GOOGLE_PLAY_CLIENT_EMAIL?: string;
  GOOGLE_PLAY_PRIVATE_KEY?: string;
};

type CachedGoogleAccessToken = {
  value: string;
  expiresAt: number;
};

let cachedGoogleAccessToken: CachedGoogleAccessToken | null = null;

export async function googlePlayAccessToken(
  env: GooglePlayLifecycleEnv,
  forceRefresh = false,
): Promise<string> {
  if (
    !forceRefresh &&
    cachedGoogleAccessToken &&
    cachedGoogleAccessToken.expiresAt > Date.now() + 60_000
  ) {
    return cachedGoogleAccessToken.value;
  }

  const email = requireCredential(
    env.GOOGLE_PLAY_CLIENT_EMAIL,
    'Google Play service-account email is not configured.',
  );
  const privateKey = requireCredential(
    env.GOOGLE_PLAY_PRIVATE_KEY,
    'Google Play service-account private key is not configured.',
  ).replace(/\\n/g, '\n');
  const key = await importPKCS8(privateKey, 'RS256');
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: 'https://www.googleapis.com/auth/androidpublisher',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(email)
    .setSubject(email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error('Google Play verification credentials were rejected.');
  }

  const body = (await response.json()) as Record<string, unknown>;
  const value = typeof body.access_token === 'string'
    ? body.access_token.trim()
    : '';
  const expiresIn = Number(body.expires_in ?? 3600);
  if (!value) throw new Error('Google Play access token was not returned.');

  cachedGoogleAccessToken = {
    value,
    expiresAt: Date.now() + Math.max(300, expiresIn) * 1000,
  };
  return value;
}

export async function acknowledgeGoogleProductPurchase(
  env: GooglePlayLifecycleEnv,
  packageName: string,
  productId: string,
  purchaseToken: string,
): Promise<boolean> {
  const url =
    'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/' +
    `${encodeURIComponent(packageName)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;

  let response = await postWithToken(url, await googlePlayAccessToken(env), {
    developerPayload: 'sudoku_game_server_verified',
  });
  if (response.status === 401) {
    response = await postWithToken(
      url,
      await googlePlayAccessToken(env, true),
      { developerPayload: 'sudoku_game_server_verified' },
    );
  }
  if (response.ok) return true;

  const text = await safeResponseText(response);
  if (
    response.status === 409 ||
    /already\s+acknowledged|already\s+acknowledge|acknowledged/i.test(text)
  ) {
    return true;
  }
  throw new Error(
    `Google Play acknowledge failed (${response.status})${text ? `: ${text}` : ''}`,
  );
}

export async function consumeGoogleProductPurchase(
  env: GooglePlayLifecycleEnv,
  packageName: string,
  productId: string,
  purchaseToken: string,
): Promise<boolean> {
  const url =
    'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/' +
    `${encodeURIComponent(packageName)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:consume`;

  let response = await postWithToken(url, await googlePlayAccessToken(env), {});
  if (response.status === 401) {
    response = await postWithToken(
      url,
      await googlePlayAccessToken(env, true),
      {},
    );
  }
  if (response.ok) return true;

  const text = await safeResponseText(response);
  if (response.status === 409 && /already|consum/i.test(text)) return true;
  throw new Error(
    `Google Play consume failed (${response.status})${text ? `: ${text}` : ''}`,
  );
}

async function postWithToken(
  url: string,
  accessToken: string,
  body: Record<string, unknown>,
): Promise<Response> {
  return fetch(url, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
}

function requireCredential(value: string | undefined, message: string): string {
  const result = value?.trim();
  if (!result || result.startsWith('REPLACE_')) throw new Error(message);
  return result;
}

async function safeResponseText(response: Response): Promise<string> {
  try {
    const text = (await response.text()).trim();
    return text.length > 500 ? text.slice(0, 500) : text;
  } catch {
    return '';
  }
}
