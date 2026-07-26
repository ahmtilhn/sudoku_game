import { describe, expect, it } from 'vitest';

import {
  applyForfeit,
  applyMove,
  applyRating,
  applyReady,
  createInitialDuelState,
  eloDelta,
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

  it('calculates Elo deltas and clamps rating bounds', () => {
    expect(eloDelta(1000, 1000, 1, 0)).toBe(20);
    expect(eloDelta(1400, 900, 1, 120)).toBeLessThan(3);
    expect(eloDelta(900, 1400, 1, 20)).toBeGreaterThan(20);
    expect(applyRating(95, -50)).toBe(100);
    expect(applyRating(2995, 50)).toBe(3000);
  });
});
