import { selectRankedPuzzle } from './ranked_puzzle_bank';

export type DuelDifficulty = 'beginner' | 'easy' | 'medium' | 'hard' | 'expert';
export type DuelMode = 'friendly' | 'ranked';
export type Seat = 'A' | 'B';
export type MatchStatus =
  | 'waiting'
  | 'countdown'
  | 'active'
  | 'paused'
  | 'completed'
  | 'forfeited'
  | 'cancelled'
  | 'abandoned';

export const TURN_DURATION_MS = 10_000;
export const READY_DEADLINE_MS = 30_000;
export const DISCONNECT_GRACE_MS = 45_000;
export const MAX_GRACE_BUDGET_MS = 60_000;

export type PlayerPublic = {
  id: string;
  publicId: string;
  username: string;
  displayName: string;
  avatarKey: string;
};

export type SeatState = {
  player: PlayerPublic;
  ready: boolean;
  connected: boolean;
  lastSeenAt: number;
  disconnectDeadline: number | null;
  graceRemainingMs: number;
};

export type RatingChange = {
  beforeGlobal: number;
  afterGlobal: number;
  deltaGlobal: number;
  beforeDifficulty: number;
  afterDifficulty: number;
  deltaDifficulty: number;
};

export type DuelState = {
  schemaVersion: 1;
  roomId: string;
  matchId: string;
  challengeId: string | null;
  mode: DuelMode;
  difficulty: DuelDifficulty;
  status: MatchStatus;
  createdAt: number;
  readyDeadline: number;
  startedAt: number | null;
  finishedAt: number | null;
  playerA: SeatState;
  playerB: SeatState;
  puzzleId: string;
  puzzleFingerprint: string;
  puzzle: number[];
  solution: number[];
  board: number[];
  scores: Record<Seat, number>;
  mistakes: Record<Seat, number>;
  correctMoves: Record<Seat, number>;
  timeouts: Record<Seat, number>;
  currentTurnSeat: Seat;
  turnNumber: number;
  turnStartedAt: number | null;
  turnDeadline: number | null;
  revision: number;
  lastProcessed: Record<string, Record<string, PublicEvent>>;
  winnerSeat: Seat | null;
  finishReason: string | null;
  settled: boolean;
  settlementAttempts: number;
  ratingResult: Record<Seat, RatingChange> | null;
};

export type ClientEnvelope = {
  v: number;
  type: string;
  requestId?: string;
  expectedRevision?: number;
  payload?: Record<string, unknown>;
};

export type PublicEvent = {
  v: 1;
  type: string;
  eventId: string;
  revision: number;
  serverTime: number;
  payload: Record<string, unknown>;
};

export function createInitialDuelState(input: {
  roomId: string;
  matchId: string;
  challengeId: string | null;
  mode: DuelMode;
  difficulty: DuelDifficulty;
  playerA: PlayerPublic;
  playerB: PlayerPublic;
  now: number;
  randomBytes: Uint8Array;
}): DuelState {
  const generated = rankedPuzzle(input.difficulty, input.randomBytes);
  const currentTurnSeat = input.randomBytes[15] % 2 === 0 ? 'A' : 'B';
  return {
    schemaVersion: 1,
    roomId: input.roomId,
    matchId: input.matchId,
    challengeId: input.challengeId,
    mode: input.mode,
    difficulty: input.difficulty,
    status: 'waiting',
    createdAt: input.now,
    readyDeadline: input.now + READY_DEADLINE_MS,
    startedAt: null,
    finishedAt: null,
    playerA: seatState(input.playerA, input.now),
    playerB: seatState(input.playerB, input.now),
    puzzleId: generated.id,
    puzzleFingerprint: generated.fingerprint,
    puzzle: generated.puzzle,
    solution: generated.solution,
    board: [...generated.puzzle],
    scores: { A: 0, B: 0 },
    mistakes: { A: 0, B: 0 },
    correctMoves: { A: 0, B: 0 },
    timeouts: { A: 0, B: 0 },
    currentTurnSeat,
    turnNumber: 1,
    turnStartedAt: null,
    turnDeadline: null,
    revision: 1,
    lastProcessed: {},
    winnerSeat: null,
    finishReason: null,
    settled: false,
    settlementAttempts: 0,
    ratingResult: null,
  };
}

export function applyReady(state: DuelState, seat: Seat, now: number): PublicEvent[] {
  if (state.status !== 'waiting') return [event(state, 'player_ready', now, { seat })];
  seatFor(state, seat).ready = true;
  state.revision++;
  const events = [event(state, 'player_ready', now, { seat })];
  if (state.playerA.ready && state.playerB.ready) {
    state.status = 'active';
    state.startedAt = now;
    state.turnStartedAt = now;
    state.turnDeadline = now + TURN_DURATION_MS;
    state.revision++;
    events.push(event(state, 'match_started', now, snapshot(state, seat, now)));
  }
  return events;
}

export function applyMove(
  state: DuelState,
  seat: Seat,
  requestId: string,
  expectedRevision: number | undefined,
  cellIndex: number,
  value: number,
  now: number,
): PublicEvent[] {
  const replay = replayEvent(state, seat, requestId);
  if (replay) return [replay];
  const timeoutEvents = applyDueDeadlines(state, now);
  if (expectedRevision !== undefined && expectedRevision < state.revision) {
    const stale = event(state, 'protocol_error', now, {
      code: 'stale_revision',
      snapshot: snapshot(state, seat, now),
    });
    remember(state, seat, requestId, stale);
    return [...timeoutEvents, stale];
  }
  if (state.status !== 'active') {
    return rejectMove(state, seat, requestId, now, 'match_not_active', timeoutEvents);
  }
  if (state.currentTurnSeat !== seat) {
    return rejectMove(state, seat, requestId, now, 'out_of_turn', timeoutEvents);
  }
  if (!Number.isInteger(cellIndex) || cellIndex < 0 || cellIndex >= 81) {
    return rejectMove(state, seat, requestId, now, 'invalid_cell', timeoutEvents);
  }
  if (!Number.isInteger(value) || value < 1 || value > 9) {
    return rejectMove(state, seat, requestId, now, 'invalid_value', timeoutEvents);
  }
  if (state.puzzle[cellIndex] !== 0 || state.board[cellIndex] !== 0) {
    return rejectMove(state, seat, requestId, now, 'cell_locked', timeoutEvents);
  }

  const correct = state.solution[cellIndex] === value;
  if (correct) {
    state.board[cellIndex] = value;
    state.scores[seat] += 10;
    state.correctMoves[seat]++;
  } else {
    state.scores[seat] -= 5;
    state.mistakes[seat]++;
  }
  state.revision++;
  const accepted = event(state, correct ? 'move_accepted' : 'move_rejected', now, {
    seat,
    cellIndex,
    value: correct ? value : undefined,
    reason: correct ? null : 'incorrect_value',
    scores: state.scores,
  });
  remember(state, seat, requestId, accepted);

  const events = [...timeoutEvents, accepted];
  if (state.board.every((cell) => cell !== 0)) {
    finishByScore(state, now, 'board_completed');
    events.push(event(state, 'match_completed', now, publicResult(state)));
  } else {
    nextTurn(state, now);
    events.push(event(state, 'turn_changed', now, turnPayload(state)));
  }
  return events;
}

export function applyForfeit(
  state: DuelState,
  seat: Seat,
  requestId: string,
  now: number,
): PublicEvent[] {
  const replay = replayEvent(state, seat, requestId);
  if (replay) return [replay];
  if (state.status === 'completed' || state.status === 'forfeited') {
    const done = event(state, 'match_completed', now, publicResult(state));
    remember(state, seat, requestId, done);
    return [done];
  }
  state.status = state.startedAt == null ? 'cancelled' : 'forfeited';
  state.finishedAt = now;
  state.winnerSeat = state.startedAt == null ? null : otherSeat(seat);
  state.finishReason = state.startedAt == null ? 'cancelled_before_start' : 'explicit_forfeit';
  state.revision++;
  const done = event(state, 'player_forfeited', now, publicResult(state));
  remember(state, seat, requestId, done);
  return [done];
}

export function applyDueDeadlines(state: DuelState, now: number): PublicEvent[] {
  const events: PublicEvent[] = [];
  if (state.status === 'waiting' && now >= state.readyDeadline) {
    state.status = 'cancelled';
    state.finishedAt = now;
    state.finishReason = 'ready_timeout';
    state.revision++;
    events.push(event(state, 'match_completed', now, publicResult(state)));
  }
  for (const seat of ['A', 'B'] as const) {
    const current = seatFor(state, seat);
    if (
      (state.status === 'active' || state.status === 'paused') &&
      current.disconnectDeadline !== null &&
      now >= current.disconnectDeadline
    ) {
      state.status = 'forfeited';
      state.finishedAt = now;
      state.winnerSeat = otherSeat(seat);
      state.finishReason = 'disconnect_forfeit';
      state.revision++;
      events.push(event(state, 'match_completed', now, publicResult(state)));
    }
  }
  if (state.status === 'active' && state.turnDeadline !== null && now >= state.turnDeadline) {
    state.timeouts[state.currentTurnSeat]++;
    state.revision++;
    events.push(event(state, 'turn_timeout', now, { seat: state.currentTurnSeat }));
    nextTurn(state, now);
    events.push(event(state, 'turn_changed', now, turnPayload(state)));
  }
  return events;
}

export function markConnected(state: DuelState, seat: Seat, now: number): PublicEvent {
  const current = seatFor(state, seat);
  current.connected = true;
  current.lastSeenAt = now;
  current.disconnectDeadline = null;
  state.revision++;
  return event(state, 'player_presence', now, { seat, connected: true });
}

export function markDisconnected(state: DuelState, seat: Seat, now: number): PublicEvent {
  const current = seatFor(state, seat);
  current.connected = false;
  current.lastSeenAt = now;
  if (state.startedAt !== null && state.status === 'active') {
    const grace = Math.min(DISCONNECT_GRACE_MS, current.graceRemainingMs);
    current.graceRemainingMs -= grace;
    current.disconnectDeadline = now + Math.max(1_000, grace);
  }
  state.revision++;
  return event(state, 'player_presence', now, {
    seat,
    connected: false,
    disconnectDeadline: current.disconnectDeadline,
  });
}

export function snapshot(state: DuelState, youSeat: Seat, now: number): Record<string, unknown> {
  return {
    protocolVersion: 1,
    roomId: state.roomId,
    matchId: state.matchId,
    mode: state.mode,
    difficulty: state.difficulty,
    status: state.status,
    youSeat,
    players: {
      A: publicSeat(state.playerA),
      B: publicSeat(state.playerB),
    },
    puzzleId: state.puzzleId,
    puzzleFingerprint: state.puzzleFingerprint,
    puzzle: state.puzzle,
    board: state.board,
    scores: state.scores,
    mistakes: state.mistakes,
    correctMoves: state.correctMoves,
    timeouts: state.timeouts,
    currentTurnSeat: state.currentTurnSeat,
    turnNumber: state.turnNumber,
    turnDeadline: state.turnDeadline,
    serverTime: now,
    ready: { A: state.playerA.ready, B: state.playerB.ready },
    presence: {
      A: state.playerA.connected,
      B: state.playerB.connected,
    },
    revision: state.revision,
    winnerSeat: state.winnerSeat,
    finishReason: state.finishReason,
    rating: state.status === 'completed' || state.status === 'forfeited'
      ? state.ratingResult
      : null,
  };
}

export function eloDelta(a: number, b: number, result: 0 | 0.5 | 1, gamesPlayed: number): number {
  const expected = 1 / (1 + 10 ** ((b - a) / 400));
  const k = gamesPlayed < 20 ? 40 : gamesPlayed < 100 ? 24 : 16;
  return Math.round(k * (result - expected));
}

export function applyRating(before: number, delta: number): number {
  return Math.max(100, Math.min(3000, before + delta));
}

function seatState(player: PlayerPublic, now: number): SeatState {
  return {
    player,
    ready: false,
    connected: false,
    lastSeenAt: now,
    disconnectDeadline: null,
    graceRemainingMs: MAX_GRACE_BUDGET_MS,
  };
}

function rejectMove(
  state: DuelState,
  seat: Seat,
  requestId: string,
  now: number,
  code: string,
  prefix: PublicEvent[],
): PublicEvent[] {
  const rejected = event(state, 'move_rejected', now, {
    seat,
    reason: code,
    snapshot: snapshot(state, seat, now),
  });
  remember(state, seat, requestId, rejected);
  return [...prefix, rejected];
}

function nextTurn(state: DuelState, now: number): void {
  state.currentTurnSeat = otherSeat(state.currentTurnSeat);
  state.turnNumber++;
  state.turnStartedAt = now;
  state.turnDeadline = now + TURN_DURATION_MS;
  state.revision++;
}

function finishByScore(state: DuelState, now: number, reason: string): void {
  state.status = 'completed';
  state.finishedAt = now;
  state.finishReason = reason;
  state.winnerSeat =
    state.scores.A === state.scores.B ? null : state.scores.A > state.scores.B ? 'A' : 'B';
  state.revision++;
}

function turnPayload(state: DuelState): Record<string, unknown> {
  return {
    currentTurnSeat: state.currentTurnSeat,
    turnNumber: state.turnNumber,
    turnDeadline: state.turnDeadline,
  };
}

function publicResult(state: DuelState): Record<string, unknown> {
  return {
    status: state.status,
    winnerSeat: state.winnerSeat,
    finishReason: state.finishReason,
    scores: state.scores,
    mistakes: state.mistakes,
    correctMoves: state.correctMoves,
    timeouts: state.timeouts,
    rating: state.ratingResult,
  };
}

function publicSeat(value: SeatState): Record<string, unknown> {
  return {
    publicId: value.player.publicId,
    username: value.player.username,
    displayName: value.player.displayName,
    avatarKey: value.player.avatarKey,
    ready: value.ready,
    connected: value.connected,
    disconnectDeadline: value.disconnectDeadline,
  };
}

function event(
  state: DuelState,
  type: string,
  now: number,
  payload: Record<string, unknown>,
): PublicEvent {
  return {
    v: 1,
    type,
    eventId: `${state.roomId}:${state.revision}:${type}`,
    revision: state.revision,
    serverTime: now,
    payload,
  };
}

function replayEvent(state: DuelState, seat: Seat, requestId: string): PublicEvent | null {
  return state.lastProcessed[seat]?.[requestId] ?? null;
}

function remember(state: DuelState, seat: Seat, requestId: string, value: PublicEvent): void {
  const bucket = (state.lastProcessed[seat] ??= {});
  bucket[requestId] = value;
  const keys = Object.keys(bucket);
  while (keys.length > 50) {
    const first = keys.shift();
    if (first) delete bucket[first];
  }
}

export function otherSeat(seat: Seat): Seat {
  return seat === 'A' ? 'B' : 'A';
}

export function seatFor(state: DuelState, seat: Seat): SeatState {
  return seat === 'A' ? state.playerA : state.playerB;
}

function rankedPuzzle(difficulty: DuelDifficulty, randomBytes: Uint8Array): {
  id: string;
  fingerprint: string;
  puzzle: number[];
  solution: number[];
} {
  const selected = selectRankedPuzzle(difficulty, randomBytes);
  return {
    id: selected.id,
    fingerprint: selected.fingerprint,
    puzzle: selected.puzzle,
    solution: selected.solution,
  };
}
