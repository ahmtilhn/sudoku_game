type Json = Record<string, unknown>;

const baseUrl = requiredEnv('SOCIAL_BACKEND_URL').replace(/\/$/, '');
const tokenA = requiredEnv('PLAYER_A_ID_TOKEN');
const tokenB = requiredEnv('PLAYER_B_ID_TOKEN');

async function main(): Promise<void> {
  const profileA = await request(tokenA, 'POST', '/v1/me', {
    displayName: 'Smoke A',
  });
  const profileB = await request(tokenB, 'POST', '/v1/me', {
    displayName: 'Smoke B',
  });
  const publicIdB = String((profileB as Json).publicId ?? '');
  if (!publicIdB) throw new Error('Player B profile did not return publicId.');

  await request(tokenA, 'POST', '/v1/friends/requests', {
    targetPublicId: publicIdB,
  }).catch(() => undefined);
  await request(tokenB, 'POST', '/v1/friends/requests/respond', {
    requesterPublicId: String((profileA as Json).publicId),
    action: 'accept',
  }).catch(() => undefined);

  const challenge = (await request(tokenA, 'POST', '/v1/challenges', {
    recipientPublicId: publicIdB,
    difficulty: 'easy',
  })) as Json;
  const accepted = (await request(
    tokenB,
    'POST',
    `/v1/challenges/${challenge.id}/respond`,
    { action: 'accept' },
  )) as Json;
  const roomId = String(accepted.roomId ?? '');
  if (!roomId) throw new Error('Accepted challenge did not return roomId.');

  console.log(`room=${roomId}`);
  console.log('Open two devices or WebSocket clients with the supplied tokens.');
  console.log('Do not log token values. Continue with ready/move/reconnect checks manually.');
}

async function request(
  token: string,
  method: string,
  path: string,
  body?: Json,
): Promise<unknown> {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/json',
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const parsed = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(`${method} ${path} failed: ${response.status} ${text}`);
  }
  return parsed;
}

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
