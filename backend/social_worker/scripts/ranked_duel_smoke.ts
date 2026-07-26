import { createHash } from 'node:crypto';
import WebSocket from 'ws';

type Json = Record<string, any>;
type TokenSet = { idToken: string; appCheckToken?: string };

const baseUrl = requiredEnv('SOCIAL_BACKEND_URL').replace(/\/$/, '');
const playerA: TokenSet = { idToken: requiredEnv('PLAYER_A_ID_TOKEN'), appCheckToken: process.env.PLAYER_A_APP_CHECK_TOKEN };
const playerB: TokenSet = { idToken: requiredEnv('PLAYER_B_ID_TOKEN'), appCheckToken: process.env.PLAYER_B_APP_CHECK_TOKEN };

async function main(): Promise<void> {
  await request(playerA, 'POST', '/v1/me', { displayName: 'Ranked A' });
  await request(playerB, 'POST', '/v1/me', { displayName: 'Ranked B' });
  const beforeA = await ratings(playerA);
  const beforeB = await ratings(playerB);
  await request(playerA, 'POST', '/v1/matchmaking/queue', { difficulty: 'medium' });
  const matched = (await request(playerB, 'POST', '/v1/matchmaking/queue', { difficulty: 'medium' })) as Json;
  const roomId = String(matched.roomId ?? '');
  if (!roomId) throw new Error('Ranked queue did not return roomId.');
  const a = await connect(playerA, roomId);
  const b = await connect(playerB, roomId);
  await a.next('connected');
  await b.next('connected');
  a.send('ready');
  b.send('ready');
  const start = await a.next('match_started');
  await b.next('match_started');
  b.send('forfeit', {}, 'ranked-forfeit', start.revision);
  const result = await a.nextAny(['player_forfeited', 'match_completed']);
  a.close();
  b.close();
  const afterA = await ratings(playerA);
  const afterB = await ratings(playerB);
  assert(changed(afterA.global, beforeA.global) || changed(afterB.global, beforeB.global), 'global rating did not change');
  assert(changed(afterA.medium, beforeA.medium) || changed(afterB.medium, beforeB.medium), 'medium rating did not change');
  for (const scope of ['beginner', 'easy', 'hard', 'expert']) {
    assertEqual(afterA[scope].rating, beforeA[scope].rating, `${scope} A changed`);
    assertEqual(afterB[scope].rating, beforeB[scope].rating, `${scope} B changed`);
  }
  const leaderboard = (await request(playerA, 'GET', '/v1/leaderboards/medium')) as Json;
  assert(Array.isArray(leaderboard.entries), 'leaderboard entries missing');
  console.log(`PASS ranked smoke match=${short(start.payload.matchId)} revision=${result.revision} result=${result.payload.finishReason}`);
}

async function ratings(tokens: TokenSet): Promise<Record<string, Json>> {
  const body = (await request(tokens, 'GET', '/v1/me/ratings')) as Json;
  return Object.fromEntries((body.ratings as Json[]).map((row) => [row.scope, row]));
}

function changed(after: Json, before: Json): boolean {
  return Number(after.rating) !== Number(before.rating);
}

async function connect(tokens: TokenSet, roomId: string): Promise<SocketClient> {
  const socket = new WebSocket(`${baseUrl.replace(/^http/, 'ws')}/v1/rooms/${encodeURIComponent(roomId)}/connect`, {
    headers: {
      authorization: `Bearer ${tokens.idToken}`,
      ...(tokens.appCheckToken ? { 'x-firebase-appcheck': tokens.appCheckToken } : {}),
    },
  });
  await new Promise<void>((resolve, reject) => {
    socket.once('open', resolve);
    socket.once('error', reject);
  });
  return new SocketClient(socket);
}

class SocketClient {
  private readonly events: Json[] = [];
  constructor(private readonly socket: WebSocket) {
    socket.on('message', (data) => this.events.push(JSON.parse(data.toString())));
  }
  send(type: string, payload: Json = {}, requestId = `${type}-${Date.now()}`, expectedRevision?: number): void {
    this.socket.send(JSON.stringify({ v: 1, type, requestId, expectedRevision, payload }));
  }
  async next(type: string): Promise<Json> {
    return this.nextAny([type]);
  }
  async nextAny(types: string[]): Promise<Json> {
    const deadline = Date.now() + 10_000;
    while (Date.now() < deadline) {
      const index = this.events.findIndex((event) => types.includes(event.type));
      if (index >= 0) return this.events.splice(index, 1)[0];
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    throw new Error(`Timed out waiting for ${types.join('|')}`);
  }
  close(): void {
    this.socket.close();
  }
}

async function request(tokens: TokenSet, method: string, path: string, body?: Json): Promise<unknown> {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${tokens.idToken}`,
      accept: 'application/json',
      ...(tokens.appCheckToken ? { 'x-firebase-appcheck': tokens.appCheckToken } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const parsed = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`${method} ${path} failed: ${response.status} ${text}`);
  return parsed;
}

function short(value: unknown): string {
  return createHash('sha256').update(String(value ?? '')).digest('hex').slice(0, 12);
}

function assert(value: boolean, message: string): void {
  if (!value) throw new Error(message);
}

function assertEqual(actual: unknown, expected: unknown, message: string): void {
  if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`);
}

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

main().catch((error) => {
  console.error(`FAIL ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
