import {
  duelVariantConfig,
  inferDuelVariant,
  type DuelVariant,
} from './sudoku_variant';

export type DuelDifficulty = 'beginner' | 'easy' | 'medium' | 'hard' | 'expert';
export type DuelMode = 'friendly' | 'ranked';
export type { DuelVariant } from './sudoku_variant';
export type Seat = 'A' | 'B';
export type MatchStatus =
  | 'waiting'
  | 'ready_window'
  | 'countdown'
  | 'active'
  | 'paused'
  | 'completed'
  | 'forfeited'
  | 'cancelled'
  | 'abandoned';

export const TURN_DURATION_SECONDS = 30;
export const TURN_DURATION_MS = TURN_DURATION_SECONDS * 1_000;
export const READY_WINDOW_SECONDS = 10;
export const READY_DEADLINE_MS = READY_WINDOW_SECONDS * 1_000;
export const LOBBY_DEADLINE_MS = 2 * 60 * 1_000;
export const DISCONNECT_GRACE_MS = 30_000;
export const MAX_GRACE_BUDGET_MS = 60_000;
export const MAX_MATCH_DURATION_MS = 30 * 60 * 1_000;
export const MAX_CONSECUTIVE_TIMEOUTS = 3;

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
  screenLoaded: boolean;
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

export type CoinSettlementResult = {
  amount: number;
  winnerSeat: Seat | null;
  loserSeat: Seat | null;
  balances: Record<Seat, number>;
  deltas: Record<Seat, number>;
};

export type DuelState = {
  schemaVersion: 1 | 2;
  roomId: string;
  matchId: string;
  challengeId: string | null;
  mode: DuelMode;
  difficulty: DuelDifficulty;
  variant?: DuelVariant;
  boardSize?: number;
  cellCount?: number;
  status: MatchStatus;
  createdAt: number;
  lobbyDeadline?: number | null;
  readyDeadline: number | null;
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
  consecutiveTimeouts?: Record<Seat, number>;
  currentTurnSeat: Seat;
  turnNumber: number;
  turnStartedAt: number | null;
  turnDeadline: number | null;
  pauseStartedAt?: number | null;
  pausedTurnRemainingMs?: number | null;
  totalPausedMs?: number;
  revision: number;
  lastProcessed: Record<string, Record<string, PublicEvent>>;
  winnerSeat: Seat | null;
  finishReason: string | null;
  settled: boolean;
  settlementAttempts: number;
  ratingResult: Record<Seat, RatingChange> | null;
  coinResult: CoinSettlementResult | null;
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

export function seatFor(state: DuelState, seat: Seat): SeatState {
  return seat === 'A' ? state.playerA : state.playerB;
}

export function otherSeat(seat: Seat): Seat {
  return seat === 'A' ? 'B' : 'A';
}

export function stateVariant(state: DuelState): DuelVariant {
  return state.variant ?? inferDuelVariant(state.puzzle.length);
}

export function stateBoardSize(state: DuelState): number {
  return state.boardSize ?? duelVariantConfig(stateVariant(state)).boardSize;
}

export function stateCellCount(state: DuelState): number {
  return state.cellCount ?? duelVariantConfig(stateVariant(state)).cellCount;
}

export function timeoutStreaks(state: DuelState): Record<Seat, number> {
  return (state.consecutiveTimeouts ??= { A: 0, B: 0 });
}

export function isTerminalStatus(status: MatchStatus): boolean {
  return (
    status === 'completed' ||
    status === 'forfeited' ||
    status === 'cancelled' ||
    status === 'abandoned'
  );
}

export function event(
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

export function replayEvent(
  state: DuelState,
  seat: Seat,
  requestId: string,
): PublicEvent | null {
  return state.lastProcessed[seat]?.[requestId] ?? null;
}

export function remember(
  state: DuelState,
  seat: Seat,
  requestId: string,
  value: PublicEvent,
): void {
  const bucket = (state.lastProcessed[seat] ??= {});
  bucket[requestId] = value;
  const keys = Object.keys(bucket);
  while (keys.length > 50) {
    const first = keys.shift();
    if (first) delete bucket[first];
  }
}
