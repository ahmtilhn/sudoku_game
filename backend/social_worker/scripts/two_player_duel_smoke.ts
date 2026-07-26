import { createHash } from 'node:crypto';
import WebSocket from 'ws';

type Json = Record<string, any>;
type TokenSet = { idToken: string; appCheckToken?: string };

const baseUrl = requiredEnv('SOCIAL_BACKEND_URL').replace(/\/$/, '');
const playerA: TokenSet = {
  idToken: requiredEnv('PLAYER_A_ID_TOKEN'),
  appCheckToken: process.env.PLAYER_A_APP_CHECK_TOKEN,
};
const playerB: TokenSet = {
  idToken: requiredEnv('PLAYER_B_ID_TOKEN'),
  appCheckToken: process.env.PLAYER_B_APP_CHECK_TOKEN,
};

async function main(): Promise<void> {
  const { roomId } = await createFriendlyRoom();
  const a = await connect('A', playerA, roomId);
  const b = await connect('B', playerB, roomId);
  const connectedA = await a.next('connected');
  const connectedB = await b.next('connected');
  assert(!JSON.stringify(connectedA).includes('solution'), 'A connected payload leaked solution');
  assert(!JSON.stringify(connectedB).includes('solution'), 'B connected payload leaked solution');

  a.send('ready');
  b.send('ready');
  const startA = await a.next('match_started');
  const startB = await b.next('match_started');
  const snapA = startA.payload;
  const snapB = startB.payload;
  assertEqual(snapA.roomId, snapB.roomId, 'room mismatch');
  assertEqual(snapA.matchId, snapB.matchId, 'match mismatch');
  assertEqual(JSON.stringify(snapA.puzzle), JSON.stringify(snapB.puzzle), 'puzzle mismatch');
  assertEqual(JSON.stringify(snapA.board), JSON.stringify(snapB.board), 'board mismatch');
  assertEqual(snapA.currentTurnSeat, snapB.currentTurnSeat, 'turn mismatch');
  assert(!('solution' in snapA), 'snapshot includes solution');

  const solution = solveSudoku([...snapA.puzzle]);
  const turnSeat = String(snapA.currentTurnSeat);
  const turnClient = turnSeat === 'A' ? a : b;
  const otherClient = turnSeat === 'A' ? b : a;
  const empty = snapA.board.findIndex((value: number) => value === 0);
  assert(empty >= 0, 'no empty cell');

  const beforeScore = scoreOf(snapA, otherClient.seat);
  otherClient.send('move', { cellIndex: empty, value: solution[empty] }, 'out-of-turn', snapA.revision);
  const rejected = await otherClient.next('move_rejected');
  assertEqual(rejected.payload.reason, 'out_of_turn', 'out of turn must reject');
  assertEqual(scoreOf(snapA, otherClient.seat), beforeScore, 'out of turn changed score');

  turnClient.send('move', { cellIndex: empty, value: solution[empty] }, 'correct', snapA.revision);
  const accepted = await turnClient.next('move_accepted');
  assertEqual(accepted.payload.cellIndex, empty, 'accepted wrong cell');
  await turnClient.next('turn_changed');
  await otherClient.next('move_accepted');
  await otherClient.next('turn_changed');

  const nextSeat = turnSeat === 'A' ? 'B' : 'A';
  const wrongClient = nextSeat === 'A' ? a : b;
  wrongClient.send('request_snapshot');
  const afterCorrect = (await wrongClient.next('snapshot')).payload;
  const wrongCell = afterCorrect.board.findIndex((value: number) => value === 0);
  const wrongValue = solution[wrongCell] === 1 ? 2 : 1;
  const wrongScoreBefore = scoreOf(afterCorrect, wrongClient.seat);
  wrongClient.send('move', { cellIndex: wrongCell, value: wrongValue }, 'wrong', afterCorrect.revision);
  const wrong = await wrongClient.next('move_rejected');
  assertEqual(wrong.payload.reason, 'incorrect_value', 'wrong value must reject');
  wrongClient.send('move', { cellIndex: wrongCell, value: wrongValue }, 'wrong', afterCorrect.revision);
  await wrongClient.next('move_rejected');
  wrongClient.send('request_snapshot');
  const afterWrong = (await wrongClient.next('snapshot')).payload;
  assertEqual(scoreOf(afterWrong, wrongClient.seat), wrongScoreBefore - 5, 'duplicate request changed score twice');

  wrongClient.send('move', { cellIndex: wrongCell, value: solution[wrongCell] }, 'stale', 1);
  const stale = await wrongClient.next('protocol_error');
  assertEqual(stale.payload.code, 'stale_revision', 'expected stale revision');

  a.close();
  const a2 = await connect('A2', playerA, roomId);
  const reconnected = await a2.next('connected');
  assertEqual(JSON.stringify(reconnected.payload.board), JSON.stringify(afterWrong.board), 'reconnect board mismatch');

  b.send('forfeit', {}, 'forfeit');
  const resultB = await b.nextAny(['player_forfeited', 'match_completed']);
  const resultA = await a2.nextAny(['player_forfeited', 'match_completed']);
  assertEqual(resultA.payload.winnerSeat, resultB.payload.winnerSeat, 'winner mismatch');
  assertEqual(resultA.payload.finishReason, resultB.payload.finishReason, 'finish reason mismatch');

  const history = (await request(playerA, 'GET', '/v1/matches/history')) as Json;
  const matches = (history.matches as Json[]).filter((match) => short(match.roomId) === short(roomId));
  assert(matches.length <= 1, 'history duplicate detected');
  a2.close();
  b.close();

  console.log(`PASS friendly smoke match=${short(snapA.matchId)} revision=${resultA.revision} result=${resultA.payload.finishReason}`);
}

async function createFriendlyRoom(): Promise<{ roomId: string }> {
  const profileA = (await request(playerA, 'POST', '/v1/me', { displayName: 'Smoke A' })) as Json;
  const profileB = (await request(playerB, 'POST', '/v1/me', { displayName: 'Smoke B' })) as Json;
  const publicIdA = String(profileA.publicId ?? '');
  const publicIdB = String(profileB.publicId ?? '');
  await request(playerA, 'POST', '/v1/friends/requests', { targetPublicId: publicIdB }).catch(() => undefined);
  await request(playerB, 'POST', '/v1/friends/requests/respond', { requesterPublicId: publicIdA, action: 'accept' }).catch(() => undefined);
  const challenge = (await request(playerA, 'POST', '/v1/challenges', { recipientPublicId: publicIdB, difficulty: 'easy' })) as Json;
  const accepted = (await request(playerB, 'POST', `/v1/challenges/${challenge.id}/respond`, { action: 'accept' })) as Json;
  const roomId = String(accepted.roomId ?? '');
  if (!roomId) throw new Error('Accepted challenge did not return roomId.');
  return { roomId };
}

async function connect(label: string, tokens: TokenSet, roomId: string): Promise<SocketClient> {
  const url = `${baseUrl.replace(/^http/, 'ws')}/v1/rooms/${encodeURIComponent(roomId)}/connect`;
  const socket = new WebSocket(url, {
    headers: {
      authorization: `Bearer ${tokens.idToken}`,
      ...(tokens.appCheckToken ? { 'x-firebase-appcheck': tokens.appCheckToken } : {}),
    },
  });
  await new Promise<void>((resolve, reject) => {
    socket.once('open', resolve);
    socket.once('error', reject);
  });
  return new SocketClient(label, socket);
}

class SocketClient {
  readonly events: Json[] = [];
  constructor(readonly seat: string, private readonly socket: WebSocket) {
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
    throw new Error(`Timed out waiting for ${types.join('|')} on ${this.seat}`);
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

function solveSudoku(board: number[]): number[] {
  const copy = [...board];
  if (!solve(copy)) throw new Error('Public puzzle could not be solved.');
  return copy;
}

function solve(board: number[]): boolean {
  const index = board.findIndex((value) => value === 0);
  if (index < 0) return true;
  for (const value of legal(board, index)) {
    board[index] = value;
    if (solve(board)) return true;
    board[index] = 0;
  }
  return false;
}

function legal(board: number[], index: number): number[] {
  const row = Math.floor(index / 9);
  const col = index % 9;
  const used = new Set<number>();
  for (let i = 0; i < 9; i++) {
    used.add(board[row * 9 + i]);
    used.add(board[i * 9 + col]);
  }
  const boxRow = Math.floor(row / 3) * 3;
  const boxCol = Math.floor(col / 3) * 3;
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) used.add(board[(boxRow + r) * 9 + boxCol + c]);
  return [1, 2, 3, 4, 5, 6, 7, 8, 9].filter((value) => !used.has(value));
}

function scoreOf(snapshot: Json, seat: string): number {
  return Number(snapshot.scores?.[seat] ?? 0);
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
