import { selectRankedPuzzle } from './ranked_puzzle_bank';
import { duelVariantConfig, type DuelVariant } from './sudoku_variant';
import {
  DISCONNECT_GRACE_MS,
  LOBBY_DEADLINE_MS,
  MAX_CONSECUTIVE_TIMEOUTS,
  MAX_MATCH_DURATION_MS,
  READY_DEADLINE_MS,
  TURN_DURATION_MS,
  type DuelDifficulty,
  type DuelMode,
  type DuelState,
  type PlayerPublic,
  type PublicEvent,
  type Seat,
  event,
  otherSeat,
  remember,
  replayEvent,
  seatFor,
  stateBoardSize,
  stateCellCount,
  timeoutStreaks,
} from './online_duel_model';
import {
  publicResult,
  readinessPayload,
  seatState,
  snapshot,
  turnPayload,
} from './online_duel_view';

export function createInitialDuelState(input: {
  roomId: string;
  matchId: string;
  challengeId: string | null;
  mode: DuelMode;
  difficulty: DuelDifficulty;
  variant?: DuelVariant;
  playerA: PlayerPublic;
  playerB: PlayerPublic;
  now: number;
  randomBytes: Uint8Array;
}): DuelState {
  const variant = input.variant ?? 'classic9';
  const config = duelVariantConfig(variant);
  const generated = selectRankedPuzzle(
    input.difficulty,
    input.randomBytes,
    variant,
  );
  const currentTurnSeat: Seat = input.randomBytes[15] % 2 === 0 ? 'A' : 'B';
  return {
    schemaVersion: 2,
    roomId: input.roomId,
    matchId: input.matchId,
    challengeId: input.challengeId,
    mode: input.mode,
    difficulty: input.difficulty,
    variant,
    boardSize: config.boardSize,
    cellCount: config.cellCount,
    status: 'waiting',
    createdAt: input.now,
    lobbyDeadline: input.now + LOBBY_DEADLINE_MS,
    readyDeadline: null,
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
    consecutiveTimeouts: { A: 0, B: 0 },
    currentTurnSeat,
    turnNumber: 1,
    turnStartedAt: null,
    turnDeadline: null,
    pauseStartedAt: null,
    pausedTurnRemainingMs: null,
    totalPausedMs: 0,
    revision: 1,
    lastProcessed: {},
    winnerSeat: null,
    finishReason: null,
    settled: false,
    settlementAttempts: 0,
    ratingResult: null,
    coinResult: null,
  };
}

export function applyReady(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent[] {
  if (state.status === 'active' || state.finishedAt !== null) {
    return [event(state, 'player_ready', now, { seat })];
  }
  const current = seatFor(state, seat);
  if (!current.ready) {
    current.ready = true;
    state.revision++;
  }
  const events = [event(state, 'player_ready', now, { seat })];
  events.push(...maybeOpenReadyWindow(state, now));
  events.push(...maybeStartMatch(state, now));
  return events;
}

export function applyScreenLoaded(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent[] {
  if (state.status === 'active' || state.finishedAt !== null) {
    return [event(state, 'screen_loaded', now, { seat })];
  }
  const current = seatFor(state, seat);
  if (!current.screenLoaded) {
    current.screenLoaded = true;
    state.revision++;
  }
  const events = [event(state, 'screen_loaded', now, { seat })];
  events.push(...maybeOpenReadyWindow(state, now));
  events.push(...maybeStartMatch(state, now));
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
    return rejectMove(
      state,
      seat,
      requestId,
      now,
      'game_not_active',
      timeoutEvents,
    );
  }
  if (state.currentTurnSeat !== seat) {
    return rejectMove(
      state,
      seat,
      requestId,
      now,
      'not_your_turn',
      timeoutEvents,
    );
  }
  if (
    !Number.isInteger(cellIndex) ||
    cellIndex < 0 ||
    cellIndex >= stateCellCount(state)
  ) {
    return rejectMove(
      state,
      seat,
      requestId,
      now,
      'invalid_cell',
      timeoutEvents,
    );
  }
  if (
    !Number.isInteger(value) ||
    value < 1 ||
    value > stateBoardSize(state)
  ) {
    return rejectMove(
      state,
      seat,
      requestId,
      now,
      'invalid_value',
      timeoutEvents,
    );
  }
  if (state.puzzle[cellIndex] !== 0 || state.board[cellIndex] !== 0) {
    return rejectMove(
      state,
      seat,
      requestId,
      now,
      state.puzzle[cellIndex] !== 0
        ? 'cell_not_editable'
        : 'cell_already_filled',
      timeoutEvents,
    );
  }

  timeoutStreaks(state)[seat] = 0;
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
  const accepted = event(
    state,
    correct ? 'move_accepted' : 'move_rejected',
    now,
    {
      seat,
      cellIndex,
      value: correct ? value : undefined,
      reason: correct ? null : 'wrong_value',
      scores: state.scores,
    },
  );
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
  state.status = state.startedAt === null ? 'cancelled' : 'forfeited';
  state.finishedAt = now;
  state.winnerSeat = state.startedAt === null ? null : otherSeat(seat);
  state.finishReason =
    state.startedAt === null
      ? 'cancelled_before_start'
      : 'explicit_forfeit';
  state.revision++;
  const done = event(state, 'player_forfeited', now, publicResult(state));
  remember(state, seat, requestId, done);
  return [done];
}

export function applyDueDeadlines(
  state: DuelState,
  now: number,
): PublicEvent[] {
  const events: PublicEvent[] = [];
  const lobbyDeadline =
    state.lobbyDeadline ?? state.createdAt + LOBBY_DEADLINE_MS;
  state.lobbyDeadline = lobbyDeadline;
  if (
    state.status === 'waiting' &&
    state.startedAt === null &&
    now >= lobbyDeadline
  ) {
    state.status = 'cancelled';
    state.finishedAt = now;
    state.winnerSeat = null;
    state.finishReason = 'lobby_timeout';
    state.revision++;
    events.push(event(state, 'match_completed', now, publicResult(state)));
    return events;
  }
  if (
    state.status === 'ready_window' &&
    state.readyDeadline !== null &&
    now >= state.readyDeadline
  ) {
    if (canStartMatch(state)) {
      events.push(...startMatch(state, now));
    } else {
      state.status = 'waiting';
      state.readyDeadline = null;
      state.revision++;
      events.push(
        event(
          state,
          'ready_window_cancelled',
          now,
          readinessPayload(state),
        ),
      );
    }
  }

  if (
    state.status === 'active' &&
    state.startedAt !== null &&
    now >= state.startedAt + MAX_MATCH_DURATION_MS + (state.totalPausedMs ?? 0)
  ) {
    finishByScore(state, now, 'max_match_duration');
    events.push(event(state, 'match_completed', now, publicResult(state)));
    return events;
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
      return events;
    }
  }

  if (
    state.status === 'active' &&
    state.turnDeadline !== null &&
    now >= state.turnDeadline
  ) {
    const timedOutSeat = state.currentTurnSeat;
    state.timeouts[timedOutSeat]++;
    const streaks = timeoutStreaks(state);
    streaks[timedOutSeat]++;
    state.revision++;
    events.push(
      event(state, 'turn_timeout', now, {
        seat: timedOutSeat,
        consecutiveTimeouts: streaks[timedOutSeat],
      }),
    );
    if (streaks[timedOutSeat] >= MAX_CONSECUTIVE_TIMEOUTS) {
      state.status = 'forfeited';
      state.finishedAt = now;
      state.winnerSeat = otherSeat(timedOutSeat);
      state.finishReason = 'consecutive_timeouts';
      state.revision++;
      events.push(event(state, 'match_completed', now, publicResult(state)));
      return events;
    }
    nextTurn(state, now);
    events.push(event(state, 'turn_changed', now, turnPayload(state)));
  }
  return events;
}

export function markConnected(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent {
  const current = seatFor(state, seat);
  current.connected = true;
  current.lastSeenAt = now;
  current.disconnectDeadline = null;

  if (
    state.status === 'paused' &&
    state.finishedAt === null &&
    state.playerA.connected &&
    state.playerB.connected
  ) {
    const pausedAt = state.pauseStartedAt ?? now;
    const remaining = Math.max(
      1_000,
      Math.min(TURN_DURATION_MS, state.pausedTurnRemainingMs ?? TURN_DURATION_MS),
    );
    state.totalPausedMs =
      (state.totalPausedMs ?? 0) + Math.max(0, now - pausedAt);
    state.status = 'active';
    state.turnDeadline = now + remaining;
    state.turnStartedAt = now - Math.max(0, TURN_DURATION_MS - remaining);
    state.pauseStartedAt = null;
    state.pausedTurnRemainingMs = null;
  }

  state.revision++;
  return event(
    state,
    'player_presence',
    now,
    readinessPayload(state, { seat, connected: true }),
  );
}

export function markDisconnected(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent {
  const current = seatFor(state, seat);
  current.connected = false;
  current.screenLoaded = false;
  current.lastSeenAt = now;

  if (
    state.startedAt !== null &&
    (state.status === 'active' || state.status === 'paused')
  ) {
    current.disconnectDeadline = now + DISCONNECT_GRACE_MS;

    if (state.status === 'active') {
      const remaining = state.turnDeadline === null
        ? TURN_DURATION_MS
        : Math.max(1_000, Math.min(TURN_DURATION_MS, state.turnDeadline - now));
      state.status = 'paused';
      state.pauseStartedAt = now;
      state.pausedTurnRemainingMs = remaining;
      state.turnDeadline = null;
    }
  }

  if (state.status === 'ready_window') {
    state.status = 'waiting';
    state.readyDeadline = null;
  }
  state.revision++;
  return event(
    state,
    'player_presence',
    now,
    readinessPayload(state, { seat, connected: false }),
  );
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

function maybeOpenReadyWindow(
  state: DuelState,
  now: number,
): PublicEvent[] {
  if (
    state.startedAt !== null ||
    state.finishedAt !== null ||
    state.readyDeadline !== null ||
    !bothConnectedAndLoaded(state)
  ) {
    return [];
  }
  state.status = 'ready_window';
  state.lobbyDeadline = null;
  state.readyDeadline = now + READY_DEADLINE_MS;
  state.revision++;
  return [
    event(state, 'ready_window_started', now, readinessPayload(state)),
  ];
}

function maybeStartMatch(state: DuelState, now: number): PublicEvent[] {
  if (
    !canStartMatch(state) ||
    !(state.playerA.ready && state.playerB.ready)
  ) {
    return [];
  }
  return startMatch(state, now);
}

function canStartMatch(state: DuelState): boolean {
  return (
    state.startedAt === null &&
    state.finishedAt === null &&
    bothConnectedAndLoaded(state)
  );
}

function bothConnectedAndLoaded(state: DuelState): boolean {
  return (
    state.playerA.connected &&
    state.playerB.connected &&
    state.playerA.screenLoaded &&
    state.playerB.screenLoaded
  );
}

function startMatch(state: DuelState, now: number): PublicEvent[] {
  if (state.startedAt !== null) return [];
  state.status = 'active';
  state.lobbyDeadline = null;
  state.startedAt = now;
  state.readyDeadline = null;
  state.turnStartedAt = now;
  state.turnDeadline = now + TURN_DURATION_MS;
  state.revision++;
  const started = event(
    state,
    'match_started',
    now,
    snapshot(state, state.currentTurnSeat, now),
  );
  return [
    started,
    {
      ...started,
      type: 'game_started',
      eventId: `${state.roomId}:${state.revision}:game_started`,
    },
  ];
}

function finishByScore(
  state: DuelState,
  now: number,
  reason: string,
): void {
  state.status = 'completed';
  state.finishedAt = now;
  state.finishReason = reason;
  state.winnerSeat =
    state.scores.A === state.scores.B
      ? null
      : state.scores.A > state.scores.B
      ? 'A'
      : 'B';
  state.revision++;
}
