import { describe, expect, it } from 'vitest';

import {
  applyForfeit,
  applyDueDeadlines,
  applyMove,
  applyRating,
  applyReady,
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

describe('authoritative online duel engine', () => {
  it('does not expose the solution in public snapshots', () => {
    const duel = state();
    const visible = snapshot(duel, 'A', 1_000);

    expect(visible).not.toHaveProperty('solution');
    expect(JSON.stringify(visible)).not.toContain(duel.solution.join(','));
  });

  it('starts only after both players are ready', () => {
    const duel = state();
    applyReady(duel, 'A', 1_001);
    expect(duel.status).toBe('waiting');

    applyReady(duel, 'B', 1_002);
    expect(duel.status).toBe('active');
    expect(duel.turnDeadline).toBe(11_002);
  });

  it('rejects out-of-turn moves without changing score', () => {
    const duel = state();
    applyReady(duel, 'A', 1_001);
    applyReady(duel, 'B', 1_002);
    const wrongSeat = duel.currentTurnSeat === 'A' ? 'B' : 'A';

    const before = { ...duel.scores };
    const events = applyMove(duel, wrongSeat, 'req-1', duel.revision, 0, 1, 1_003);

    expect(events.at(-1)?.type).toBe('move_rejected');
    expect(events.at(-1)?.payload.reason).toBe('out_of_turn');
    expect(duel.scores).toEqual(before);
  });

  it('accepts correct moves, advances turn, and deduplicates request IDs', () => {
    const duel = state();
    applyReady(duel, 'A', 1_001);
    applyReady(duel, 'B', 1_002);
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
    applyReady(duel, 'A', 1_001);
    applyReady(duel, 'B', 1_002);
    const seat = duel.currentTurnSeat;
    const cellIndex = duel.board.findIndex((value) => value === 0);

    const events = applyMove(duel, seat, 'stale-1', 1, cellIndex, 1, 1_003);

    expect(events.at(-1)?.type).toBe('protocol_error');
    expect(events.at(-1)?.payload.code).toBe('stale_revision');
    expect(events.at(-1)?.payload.snapshot).toBeTruthy();
  });

  it('settles explicit forfeit with the opponent as winner', () => {
    const duel = state();
    applyReady(duel, 'A', 1_001);
    applyReady(duel, 'B', 1_002);

    applyForfeit(duel, 'A', 'ff-1', 1_003);

    expect(duel.status).toBe('forfeited');
    expect(duel.winnerSeat).toBe('B');
    expect(duel.finishReason).toBe('explicit_forfeit');
  });

  it('rejects invalid, fixed, and filled cell moves', () => {
    const duel = state();
    applyReady(duel, 'A', 1_001);
    applyReady(duel, 'B', 1_002);
    const seat = duel.currentTurnSeat;
    const fixed = duel.puzzle.findIndex((value) => value !== 0);
    const empty = duel.puzzle.findIndex((value) => value === 0);

    expect(applyMove(duel, seat, 'bad-index', duel.revision, -1, 1, 1_003).at(-1)?.payload.reason).toBe('invalid_cell');
    expect(applyMove(duel, seat, 'bad-value', duel.revision, empty, 10, 1_004).at(-1)?.payload.reason).toBe('invalid_value');
    expect(applyMove(duel, seat, 'fixed', duel.revision, fixed, duel.solution[fixed], 1_005).at(-1)?.payload.reason).toBe('cell_locked');

    applyMove(duel, seat, 'correct-filled', duel.revision, empty, duel.solution[empty], 1_006);
    const other = seat === 'A' ? 'B' : 'A';
    expect(applyMove(duel, other, 'filled', duel.revision, empty, duel.solution[empty], 1_007).at(-1)?.payload.reason).toBe('cell_locked');
  });

  it('server timeout advances turn without changing score', () => {
    const duel = state();
    applyReady(duel, 'A', 1_001);
    applyReady(duel, 'B', 1_002);
    const seat = duel.currentTurnSeat;
    const before = { ...duel.scores };

    const events = applyDueDeadlines(duel, 11_003);

    expect(events.map((event) => event.type)).toContain('turn_timeout');
    expect(duel.currentTurnSeat).not.toBe(seat);
    expect(duel.scores).toEqual(before);
    expect(duel.timeouts[seat]).toBe(1);
  });

  it('disconnect grace allows reconnect before forfeit', () => {
    const duel = state();
    applyReady(duel, 'A', 1_001);
    applyReady(duel, 'B', 1_002);
    markConnected(duel, 'A', 1_003);
    markDisconnected(duel, 'A', 1_004);
    expect(duel.playerA.disconnectDeadline).toBeGreaterThan(1_004);

    markConnected(duel, 'A', 2_000);
    applyDueDeadlines(duel, 50_000);

    expect(duel.status).toBe('active');
    expect(duel.playerA.disconnectDeadline).toBeNull();
  });

  it('disconnect grace expiry forfeits to the opponent', () => {
    const duel = state();
    applyReady(duel, 'A', 1_001);
    applyReady(duel, 'B', 1_002);
    markDisconnected(duel, 'A', 1_003);

    applyDueDeadlines(duel, 50_000);

    expect(duel.status).toBe('forfeited');
    expect(duel.winnerSeat).toBe('B');
    expect(duel.finishReason).toBe('disconnect_forfeit');
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
