import { SignJWT, importPKCS8 } from 'jose';

export interface PushEnv {
  DB: D1Database;
  FCM_PROJECT_ID?: string;
  FCM_CLIENT_EMAIL?: string;
  FCM_PRIVATE_KEY?: string;
}

export type PushMessage = {
  titleKey: string;
  bodyKey: string;
  data: Record<string, string>;
  tag: string;
  /** Maximum time this notification remains useful while a device is offline. */
  ttlSeconds?: number;
};

type CachedAccessToken = {
  token: string;
  expiresAt: number;
};

let cachedAccessToken: CachedAccessToken | null = null;

export async function sendPlayerPush(
  env: PushEnv,
  playerId: string,
  message: PushMessage,
): Promise<void> {
  if (
    !env.FCM_PROJECT_ID ||
    !env.FCM_CLIENT_EMAIL ||
    !env.FCM_PRIVATE_KEY ||
    env.FCM_PROJECT_ID.startsWith('REPLACE_')
  ) {
    console.warn('FCM secrets are not configured; push notification skipped.');
    return;
  }

  const tokens = await env.DB.prepare(
    `SELECT id, token FROM device_tokens
     WHERE player_id = ? AND enabled = 1`,
  )
    .bind(playerId)
    .all<{ id: string; token: string }>();
  if (tokens.results.length === 0) return;

  const accessToken = await getAccessToken(env);
  const ttlSeconds = notificationTtlSeconds(message);
  const expiresAtSeconds = Math.floor(Date.now() / 1000) + ttlSeconds;

  await Promise.all(
    tokens.results.map(async (device) => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FCM_PROJECT_ID!)}/messages:send`,
        {
          method: 'POST',
          headers: {
            authorization: `Bearer ${accessToken}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              data: message.data,
              android: {
                priority: 'high',
                ttl: `${ttlSeconds}s`,
                notification: {
                  channel_id: 'online_challenges',
                  tag: message.tag,
                  sound: 'default',
                  title_loc_key: message.titleKey,
                  body_loc_key: message.bodyKey,
                },
              },
              apns: {
                headers: {
                  'apns-priority': '10',
                  'apns-push-type': 'alert',
                  'apns-expiration': String(expiresAtSeconds),
                },
                payload: {
                  aps: {
                    alert: {
                      'title-loc-key': message.titleKey,
                      'loc-key': message.bodyKey,
                    },
                    sound: 'default',
                    'thread-id': 'online-challenges',
                  },
                },
              },
            },
          }),
        },
      );

      if (response.ok) return;
      const text = await response.text();
      console.error('FCM send failed', response.status, text);
      if (
        text.includes('UNREGISTERED') ||
        text.includes('registration-token-not-registered')
      ) {
        await env.DB.prepare(
          'UPDATE device_tokens SET enabled = 0 WHERE id = ?',
        )
          .bind(device.id)
          .run();
      }
    }),
  );
}

function notificationTtlSeconds(message: PushMessage): number {
  if (message.ttlSeconds != null) {
    return Math.max(0, Math.min(Math.floor(message.ttlSeconds), 28 * 24 * 60 * 60));
  }

  switch (message.data.type) {
    case 'rematch_invitation':
      return 15;
    case 'challenge':
    case 'challenge_response':
      return 15 * 60;
    case 'friend_request':
    case 'friend_response':
      return 7 * 24 * 60 * 60;
    default:
      return 60 * 60;
  }
}

async function getAccessToken(env: PushEnv): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.token;
  }

  const privateKey = env.FCM_PRIVATE_KEY!.replace(/\\n/g, '\n');
  const key = await importPKCS8(privateKey, 'RS256');
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(env.FCM_CLIENT_EMAIL!)
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
    throw new Error(`FCM OAuth failed: ${await response.text()}`);
  }
  const body = (await response.json()) as {
    access_token: string;
    expires_in: number;
  };
  cachedAccessToken = {
    token: body.access_token,
    expiresAt: Date.now() + body.expires_in * 1000,
  };
  return body.access_token;
}
