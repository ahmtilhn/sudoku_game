import { describe, expect, it } from 'vitest';

import {
  applyForfeit,
  applyMove,
  applyReady,
  createInitialDuelState,
  snapshot,
} from '../src/online_duel';

describe('local two-client protocol simulation', () => {
  it('keeps two client snapshots converged through move, rejection, and forfeit', () => {
    const duel = createInitialDuelState({
      roomId: 'room-local',
      matchId: 'match-local',
      challengeId: 'challenge-local',
      mode: 'friendly',
      difficulty: 'easy',
      playerA: {
        id: 'a',
        publicId: 'pa',
        username: 'alice',
        displayName: 'Alice',
        avatarKey: 'default',
      },
      playerB: {
        id: 'b',
        publicId: 'pb',
        username: 'bob',
        displayName: 'Bob',
        avatarKey: 'default',
      },
      now: 10,
      randomBytes: new Uint8Array([7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6]),
    });

    applyReady(duel, 'A', 11);
    applyReady(duel, 'B', 12);
    const aStart = snapshot(duel, 'A', 12);
    const bStart = snapshot(duel, 'B', 12);
    expect(aStart.roomId).toBe(bStart.roomId);
    expect(aStart.matchId).toBe(bStart.matchId);
    expect(aStart.puzzle).toEqual(bStart.puzzle);
    expect(aStart.board).toEqual(bStart.board);
    expect(aStart).not.toHaveProperty('solution');

    const seat = duel.currentTurnSeat;
    const other = seat === 'A' ? 'B' : 'A';
    const empty = duel.board.findIndex((value) => value === 0);
    const wrongOutOfTurn = applyMove(duel, other, 'oot', duel.revision, empty, duel.solution[empty], 13);
    expect(wrongOutOfTurn.at(-1)?.payload.reason).toBe('out_of_turn');

    applyMove(duel, seat, 'correct', duel.revision, empty, duel.solution[empty], 14);
    expect(duel.board[empty]).toBe(duel.solution[empty]);
    expect(duel.scores[seat]).toBe(10);
    expect(snapshot(duel, 'A', 15).board).toEqual(snapshot(duel, 'B', 15).board);

    const nextSeat = duel.currentTurnSeat;
    const wrongCell = duel.board.findIndex((value) => value === 0);
    const wrongValue = duel.solution[wrongCell] === 1 ? 2 : 1;
    applyMove(duel, nextSeat, 'wrong', duel.revision, wrongCell, wrongValue, 16);
    const scoreAfterWrong = duel.scores[nextSeat];
    applyMove(duel, nextSeat, 'wrong', duel.revision, wrongCell, wrongValue, 17);
    expect(duel.scores[nextSeat]).toBe(scoreAfterWrong);

    applyForfeit(duel, 'B', 'forfeit', 18);
    const aEnd = snapshot(duel, 'A', 19);
    const bEnd = snapshot(duel, 'B', 19);
    expect(aEnd.winnerSeat).toBe(bEnd.winnerSeat);
    expect(aEnd.finishReason).toBe('explicit_forfeit');
  });
});
