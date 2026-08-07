import {
  MAX_MATCH_DURATION_MS,
  type DuelState,
  type PlayerPublic,
  type PublicEvent,
  type Seat,
  type SeatState,
  event,
  isTerminalStatus,
  stateBoardSize,
  stateCellCount,
  stateVariant,
  timeoutStreaks,
} from './online_duel_model';

export function snapshot(
  state: DuelState,
  youSeat: Seat,
  now: number,
): Record<string, unknown> {
  return {
    protocolVersion: 1,
    roomId: state.roomId,
    matchId: state.matchId,
    mode: state.mode,
    difficulty: state.difficulty,
    variant: stateVariant(state),
    boardSize: stateBoardSize(state),
    cellCount: stateCellCount(state),
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
    consecutiveTimeouts: timeoutStreaks(state),
    currentTurnSeat: state.currentTurnSeat,
    turnNumber: state.turnNumber,
    turnDeadline: state.turnDeadline,
    pausedTurnRemainingMs: state.pausedTurnRemainingMs ?? null,
    lobbyDeadline: state.lobbyDeadline ?? null,
    readyDeadline: state.readyDeadline,
    matchDeadline:
      state.startedAt === null
        ? null
        : state.startedAt + MAX_MATCH_DURATION_MS + (state.totalPausedMs ?? 0),
    serverTime: now,
    ready: { A: state.playerA.ready, B: state.playerB.ready },
    presence: { A: state.playerA.connected, B: state.playerB.connected },
    screenLoaded: {
      A: state.playerA.screenLoaded,
      B: state.playerB.screenLoaded,
    },
    revision: state.revision,
    winnerSeat: state.winnerSeat,
    finishReason: state.finishReason,
    rating:
      state.settled && isTerminalStatus(state.status)
        ? state.ratingResult
        : null,
    coinSettlement:
      state.settled && isTerminalStatus(state.status)
        ? state.coinResult
        : null,
  };
}

export function publicResult(state: DuelState): Record<string, unknown> {
  return {
    status: state.status,
    variant: stateVariant(state),
    boardSize: stateBoardSize(state),
    cellCount: stateCellCount(state),
    difficulty: state.difficulty,
    winnerSeat: state.winnerSeat,
    finishReason: state.finishReason,
    scores: state.scores,
    mistakes: state.mistakes,
    correctMoves: state.correctMoves,
    timeouts: state.timeouts,
    consecutiveTimeouts: timeoutStreaks(state),
    rating: state.ratingResult,
    coinSettlement: state.coinResult,
  };
}

export function readinessPayload(
  state: DuelState,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    status: state.status,
    readyDeadline: state.readyDeadline,
    turnDeadline: state.turnDeadline,
    pausedTurnRemainingMs: state.pausedTurnRemainingMs ?? null,
    ready: { A: state.playerA.ready, B: state.playerB.ready },
    presence: { A: state.playerA.connected, B: state.playerB.connected },
    disconnectDeadlines: {
      A: state.playerA.disconnectDeadline,
      B: state.playerB.disconnectDeadline,
    },
    screenLoaded: {
      A: state.playerA.screenLoaded,
      B: state.playerB.screenLoaded,
    },
    ...extra,
  };
}

export function turnPayload(state: DuelState): Record<string, unknown> {
  return {
    currentTurnSeat: state.currentTurnSeat,
    turnNumber: state.turnNumber,
    turnDeadline: state.turnDeadline,
  };
}

export function matchEvent(
  state: DuelState,
  type: string,
  now: number,
  payload: Record<string, unknown>,
): PublicEvent {
  return event(state, type, now, payload);
}

function publicSeat(value: SeatState): Record<string, unknown> {
  return {
    publicId: value.player.publicId,
    username: value.player.username,
    displayName: value.player.displayName,
    avatarKey: value.player.avatarKey,
    ready: value.ready,
    screenLoaded: value.screenLoaded,
    connected: value.connected,
    disconnectDeadline: value.disconnectDeadline,
  };
}

export function seatState(player: PlayerPublic, now: number): SeatState {
  return {
    player,
    ready: false,
    screenLoaded: false,
    connected: false,
    lastSeenAt: now,
    disconnectDeadline: null,
    graceRemainingMs: 60_000,
  };
}

export function eloDelta(
  a: number,
  b: number,
  result: 0 | 0.5 | 1,
  gamesPlayed: number,
): number {
  const expected = 1 / (1 + 10 ** ((b - a) / 400));
  const k = gamesPlayed < 20 ? 40 : gamesPlayed < 100 ? 24 : 16;
  return Math.round(k * (result - expected));
}

export function applyRating(before: number, delta: number): number {
  return Math.max(100, Math.min(3000, before + delta));
}
