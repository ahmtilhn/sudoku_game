import { describe, expect, it } from 'vitest';

import {
  applyMove,
  createInitialDuelState,
  roomIdForVariant,
  snapshot,
  variantFromRoomId,
} from '../src/online_duel';
import { normalizeDuelVariant } from '../src/sudoku_variant';

const player = (id: string) => ({
  id,
  publicId: id.toUpperCase(),
  username: id,
  displayName: id,
  avatarKey: 'default',
});

function classic16State() {
  return createInitialDuelState({
    roomId: 'room-16',
    matchId: 'match-16',
    challengeId: null,
    mode: 'ranked',
    difficulty: 'medium',
    variant: 'classic16',
    playerA: player('alice'),
    playerB: player('bob'),
    now: 1_000,
    randomBytes: new Uint8Array([
      1, 2, 3, 4, 5, 6, 7, 8,
      9, 10, 11, 12, 13, 14, 15, 16,
    ]),
  });
}

describe('variant-aware online duel engine', () => {
  it('normalizes legacy and current duel variants consistently', () => {
    expect(normalizeDuelVariant('classic')).toBe('classic9');
    expect(normalizeDuelVariant('classic9')).toBe('classic9');
    expect(normalizeDuelVariant('classic16')).toBe('classic16');
    expect(normalizeDuelVariant('samurai')).toBe('samurai');
    expect(() => normalizeDuelVariant('16x16')).toThrow('Invalid Sudoku variant.');
  });

  it('keeps room ids variant-prefixed for matchmaking and room startup', () => {
    const classic9Room = roomIdForVariant('classic9', 'match-9');
    const classic16Room = roomIdForVariant('classic16', 'match-16');

    expect(classic9Room).toBe('classic9:match-9');
    expect(classic16Room).toBe('classic16:match-16');
    expect(variantFromRoomId(classic9Room)).toBe('classic9');
    expect(variantFromRoomId(classic16Room)).toBe('classic16');
  });

  it('creates a numeric 16x16 room with dynamic metadata', () => {
    const duel = classic16State();
    const visible = snapshot(duel, 'A', 1_000);

    expect(duel.variant).toBe('classic16');
    expect(duel.boardSize).toBe(16);
    expect(duel.cellCount).toBe(256);
    expect(duel.puzzle).toHaveLength(256);
    expect(duel.solution).toHaveLength(256);
    expect(Math.max(...duel.solution)).toBe(16);
    expect(Math.min(...duel.solution)).toBe(1);
    expect(visible).toMatchObject({
      variant: 'classic16',
      boardSize: 16,
      cellCount: 256,
      difficulty: 'medium',
    });
    expect(visible).not.toHaveProperty('solution');
  });

  it('accepts value 16 and validates indexes against 256 cells', () => {
    const duel = classic16State();
    duel.status = 'active';
    duel.startedAt = 1_000;
    duel.currentTurnSeat = 'A';
    duel.turnDeadline = 100_000;

    const value16Index = duel.solution.findIndex(
      (value, index) => value === 16 && duel.puzzle[index] === 0,
    );
    expect(value16Index).toBeGreaterThanOrEqual(0);

    const accepted = applyMove(
      duel,
      'A',
      'value-16',
      duel.revision,
      value16Index,
      16,
      1_100,
    );
    expect(accepted.some((item) => item.type === 'move_accepted')).toBe(true);
    expect(duel.board[value16Index]).toBe(16);

    duel.currentTurnSeat = 'B';
    const invalidIndex = applyMove(
      duel,
      'B',
      'index-256',
      duel.revision,
      256,
      1,
      1_200,
    );
    expect(invalidIndex.at(-1)?.payload.reason).toBe('invalid_cell');

    const invalidValue = applyMove(
      duel,
      'B',
      'value-17',
      duel.revision,
      duel.puzzle.findIndex((value) => value === 0),
      17,
      1_300,
    );
    expect(invalidValue.at(-1)?.payload.reason).toBe('invalid_value');
  });

  it('keeps legacy rooms on classic9 when variant is omitted', () => {
    const duel = createInitialDuelState({
      roomId: 'legacy-room',
      matchId: 'legacy-match',
      challengeId: null,
      mode: 'friendly',
      difficulty: 'easy',
      playerA: player('alice'),
      playerB: player('bob'),
      now: 1_000,
      randomBytes: new Uint8Array(16),
    });

    expect(duel.variant).toBe('classic9');
    expect(duel.boardSize).toBe(9);
    expect(duel.cellCount).toBe(81);
    expect(duel.puzzle).toHaveLength(81);
  });
});
