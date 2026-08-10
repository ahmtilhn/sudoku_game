import { describe, expect, it } from 'vitest';

import {
  DISCONNECT_GRACE_MS,
  LOBBY_DEADLINE_MS,
  MAX_CONSECUTIVE_TIMEOUTS,
  MAX_MATCH_DURATION_MS,
  applyForfeit,
  applyDueDeadlines,
  applyMove,
  applyRating,
  applyReady,
  applyScreenLoaded,
  createInitialDuelState,
  eloDelta,
  markConnected,
  markDisconnected,
  snapshot,
} from '../src/online_duel';

function state() {
  return createInitialDuelState({
    roomId: 'room-1',
    matchId: 'match-1',
    challengeId: null,
    mode: 'ranked',
    difficulty: 'medium',
    playerA: {
      id: 'a',
      publicId: 'A',
      username: 'alice',
      displayName: 'Alice',
      avatarKey: 'default',
    },
    playerB: {
      id: 'b',
      publicId: 'B',
      username: 'bob',
      displayName: 'Bob',
      avatarKey: 'default',
    },
    now: 1_000,
    randomBytes: new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 4, 5, 6, 7]),
  });
}

function startDuel(duel: ReturnType<typeof state>, now = 1_000) {
  markConnected(duel, 'A', now + 1);
  markConnected(duel, 'B', now + 2);
  applyScreenLoaded(duel, 'A', now + 3);
  applyScreenLoaded(duel, 'B', now + 4);
  applyReady(duel, 'A', now + 5);
  applyReady(duel, 'B', now + 6);
}

describe('authoritative online duel engine', () => {
  it('does not expose the solution in public snapshots', () => {
    const duel = state();
    const visible = snapshot(duel, 'A', 1_000);

    expect(visible).not.toHaveProperty('solution');
    expect(JSON.stringify(visible)).not.toContain(duel.solution.join(','));
  });

  it('does not start ready deadline until both players loaded the game screen', () => {
    const duel = state();
    markConnected(duel, 'A', 1_001);
    markConnected(duel, 'B', 1_002);
    applyScreenLoaded(duel, 'A', 1_003);
    applyReady(duel, 'A', 1_004);

    expect(duel.status).toBe('waiting');
    expect(duel.readyDeadline).toBeNull();

    applyScreenLoaded(duel, 'B', 1_005);
    expect(duel.status).toBe('ready_window');
    expect(duel.readyDeadline).toBe(11_005);
  });

  it('starts immediately once both loaded players are ready', () => {
    const duel = state();
    markConnected(duel, 'A', 1_001);
    markConnected(duel, 'B', 1_002);
    applyScreenLoaded(duel, 'A', 1_003);
    applyScreenLoaded(duel, 'B', 1_004);
    applyReady(duel, 'A', 1_005);
    expect(duel.status).toBe('ready_window');

    const events = applyReady(duel, 'B', 1_006);
    expect(duel.status).toBe('active');
    expect(duel.turnDeadline).toBe(31_006);
    expect(events.filter((event) => event.type === 'match_started')).toHaveLength(1);
    expect(events.filter((event) => event.type === 'game_started')).toHaveLength(1);
  });

  it('auto-starts after the ready window when both players remain loaded', () => {
    const duel = state();
    markConnected(duel, 'A', 1_001);
    markConnected(duel, 'B', 1_002);
    applyScreenLoaded(duel, 'A', 1_003);
    applyScreenLoaded(duel, 'B', 1_004);

    const events = applyDueDeadlines(duel, 11_004);

    expect(duel.status).toBe('active');
    expect(duel.turnDeadline).toBe(41_004);
    expect(events.filter((event) => event.type === 'game_started')).toHaveLength(1);
  });

  it('does not auto-start ready window while a loaded player is disconnected', () => {
    const duel = state();
    markConnected(duel, 'A', 1_001);
    markConnected(duel, 'B', 1_002);
    applyScreenLoaded(duel, 'A', 1_003);
    applyScreenLoaded(duel, 'B', 1_004);
    markDisconnected(duel, 'B', 1_005);

    applyDueDeadlines(duel, 11_004);

    expect(duel.status).toBe('waiting');
    expect(duel.startedAt).toBeNull();
  });

  it('rejects out-of-turn moves without changing score', () => {
    const duel = state();
    startDuel(duel);
    const wrongSeat = duel.currentTurnSeat === 'A' ? 'B' : 'A';

    const before = { ...duel.scores };
    const events = applyMove(duel, wrongSeat, 'req-1', duel.revision, 0, 1, 1_003);

    expect(events.at(-1)?.type).toBe('move_rejected');
    expect(events.at(-1)?.payload.reason).toBe('not_your_turn');
    expect(duel.scores).toEqual(before);
  });

  it('accepts correct moves, advances turn, and deduplicates request IDs', () => {
    const duel = state();
    startDuel(duel);
    const seat = duel.currentTurnSeat;
    const cellIndex = duel.board.findIndex((value) => value === 0);
    const value = duel.solution[cellIndex];

    applyMove(duel, seat, 'move-1', duel.revision, cellIndex, value, 1_003);
    const afterFirst = { score: duel.scores[seat], revision: duel.revision };
    applyMove(duel, seat, 'move-1', duel.revision, cellIndex, value, 1_004);

    expect(duel.board[cellIndex]).toBe(value);
    expect(afterFirst.score).toBe(10);
    expect(duel.scores[seat]).toBe(afterFirst.score);
    expect(duel.revision).toBe(afterFirst.revision);
  });

  it('returns stale revision errors with a recovery snapshot', () => {
    const duel = state();
    startDuel(duel);
    const seat = duel.currentTurnSeat;
    const cellIndex = duel.board.findIndex((value) => value === 0);

    const events = applyMove(duel, seat, 'stale-1', 1, cellIndex, 1, 1_003);

    expect(events.at(-1)?.type).toBe('protocol_error');
    expect(events.at(-1)?.payload.code).toBe('stale_revision');
    expect(events.at(-1)?.payload.snapshot).toBeTruthy();
  });

  it('cancels and refunds a room forfeited before the match starts', () => {
    const duel = state();

    applyForfeit(duel, 'A', 'cancel-before-start', 1_003);

    expect(duel.status).toBe('cancelled');
    expect(duel.winnerSeat).toBeNull();
    expect(duel.finishReason).toBe('cancelled_before_start');
  });

  it('cancels an abandoned lobby after the server deadline', () => {
    const duel = state();

    const events = applyDueDeadlines(duel, duel.createdAt + LOBBY_DEADLINE_MS);

    expect(duel.status).toBe('cancelled');
    expect(duel.finishReason).toBe('lobby_timeout');
    expect(events.map((event) => event.type)).toContain('match_completed');
  });

  it('settles explicit forfeit with the opponent as winner', () => {
    const duel = state();
    startDuel(duel);

    applyForfeit(duel, 'A', 'ff-1', 1_003);

    expect(duel.status).toBe('forfeited');
    expect(duel.winnerSeat).toBe('B');
    expect(duel.finishReason).toBe('explicit_forfeit');
  });

  it('rejects invalid, fixed, and filled cell moves', () => {
    const duel = state();
    startDuel(duel);
    const seat = duel.currentTurnSeat;
    const fixed = duel.puzzle.findIndex((value) => value !== 0);
    const empty = duel.puzzle.findIndex((value) => value === 0);

    expect(applyMove(duel, seat, 'bad-index', duel.revision, -1, 1, 1_003).at(-1)?.payload.reason).toBe('invalid_cell');
    expect(applyMove(duel, seat, 'bad-value', duel.revision, empty, 10, 1_004).at(-1)?.payload.reason).toBe('invalid_value');
    expect(applyMove(duel, seat, 'fixed', duel.revision, fixed, duel.solution[fixed], 1_005).at(-1)?.payload.reason).toBe('cell_not_editable');

    applyMove(duel, seat, 'correct-filled', duel.revision, empty, duel.solution[empty], 1_006);
    const other = seat === 'A' ? 'B' : 'A';
    expect(applyMove(duel, other, 'filled', duel.revision, empty, duel.solution[empty], 1_007).at(-1)?.payload.reason).toBe('cell_already_filled');
  });

  it('server timeout advances turn without changing score', () => {
    const duel = state();
    startDuel(duel);
    const seat = duel.currentTurnSeat;
    const before = { ...duel.scores };

    const events = applyDueDeadlines(duel, 31_007);

    expect(events.map((event) => event.type)).toContain('turn_timeout');
    expect(duel.currentTurnSeat).not.toBe(seat);
    expect(duel.scores).toEqual(before);
    expect(duel.timeouts[seat]).toBe(1);
  });

  it('forfeits after three consecutive timeouts by the same player', () => {
    const duel = state();
    startDuel(duel);
    const seat = duel.currentTurnSeat;

    for (let attempt = 1; attempt <= MAX_CONSECUTIVE_TIMEOUTS; attempt++) {
      duel.currentTurnSeat = seat;
      duel.turnDeadline = 40_000 + attempt;
      applyDueDeadlines(duel, 40_000 + attempt);
    }

    expect(duel.status).toBe('forfeited');
    expect(duel.winnerSeat).toBe(seat === 'A' ? 'B' : 'A');
    expect(duel.finishReason).toBe('consecutive_timeouts');
    expect(duel.consecutiveTimeouts?.[seat]).toBe(MAX_CONSECUTIVE_TIMEOUTS);
  });

  it('closes a match at the maximum duration using the current score', () => {
    const duel = state();
    startDuel(duel);
    const startedAt = duel.startedAt!;
    duel.scores.A = 20;
    duel.scores.B = 10;

    const events = applyDueDeadlines(
      duel,
      startedAt + MAX_MATCH_DURATION_MS,
    );

    expect(events.map((event) => event.type)).toContain('match_completed');
    expect(duel.status).toBe('completed');
    expect(duel.winnerSeat).toBe('A');
    expect(duel.finishReason).toBe('max_match_duration');
  });

  it('pauses the match and preserves the remaining turn time during reconnect', () => {
    const duel = state();
    startDuel(duel);
    const disconnectAt = 5_000;
    const originalDeadline = duel.turnDeadline!;
    const remaining = originalDeadline - disconnectAt;

    markDisconnected(duel, 'A', disconnectAt);

    expect(duel.status).toBe('paused');
    expect(duel.turnDeadline).toBeNull();
    expect(duel.pausedTurnRemainingMs).toBe(remaining);
    expect(duel.playerA.disconnectDeadline).toBe(
      disconnectAt + DISCONNECT_GRACE_MS,
    );

    const reconnectAt = 20_000;
    markConnected(duel, 'A', reconnectAt);

    expect(duel.status).toBe('active');
    expect(duel.playerA.disconnectDeadline).toBeNull();
    expect(duel.pausedTurnRemainingMs).toBeNull();
    expect(duel.turnDeadline).toBe(reconnectAt + remaining);

    const events = applyDueDeadlines(duel, reconnectAt + remaining - 1);
    expect(events.map((event) => event.type)).not.toContain('turn_timeout');
  });

  it('uses a 30 second reconnect window', () => {
    expect(DISCONNECT_GRACE_MS).toBe(30_000);
  });

  it('disconnect grace expiry forfeits to the opponent', () => {
    const duel = state();
    startDuel(duel);
    const disconnectAt = 5_000;
    markDisconnected(duel, 'A', disconnectAt);

    applyDueDeadlines(duel, disconnectAt + DISCONNECT_GRACE_MS);

    expect(duel.status).toBe('forfeited');
    expect(duel.winnerSeat).toBe('B');
    expect(duel.finishReason).toBe('disconnect_forfeit');
  });

  it('migrates old stored state without timeout streak fields', () => {
    const duel = state();
    delete duel.consecutiveTimeouts;
    const visible = snapshot(duel, 'A', 1_000);

    expect(duel.consecutiveTimeouts).toEqual({ A: 0, B: 0 });
    expect(visible.consecutiveTimeouts).toEqual({ A: 0, B: 0 });
  });

  it('uses a backend-only puzzle bank with valid clue ranges', () => {
    const duel = state();
    const clues = duel.puzzle.filter((value) => value !== 0).length;

    expect(duel.puzzleId).toContain('medium-');
    expect(clues).toBeGreaterThanOrEqual(32);
    expect(clues).toBeLessThanOrEqual(35);
    expect(snapshot(duel, 'A', 1_000)).not.toHaveProperty('solution');
  });

  it('calculates Elo deltas and clamps rating bounds', () => {
    expect(eloDelta(1000, 1000, 1, 0)).toBe(20);
    expect(eloDelta(1400, 900, 1, 120)).toBeLessThan(3);
    expect(eloDelta(900, 1400, 1, 20)).toBeGreaterThan(20);
    expect(applyRating(95, -50)).toBe(100);
    expect(applyRating(2995, 50)).toBe(3000);
  });
});
