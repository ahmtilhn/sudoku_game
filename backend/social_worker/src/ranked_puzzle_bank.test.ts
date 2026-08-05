import { describe, expect, it } from 'vitest';

import { selectRankedPuzzle } from './ranked_puzzle_bank';
import type { DuelDifficulty } from './online_duel';

const canvasSize = 21;
const origins = [
  [0, 0],
  [0, 12],
  [6, 6],
  [12, 0],
  [12, 12],
] as const;

const units = origins.flatMap(([rowOrigin, columnOrigin]) => {
  const result: number[][] = [];
  for (let row = 0; row < 9; row++) {
    result.push(Array.from({ length: 9 }, (_, column) =>
      (rowOrigin + row) * canvasSize + columnOrigin + column,
    ));
  }
  for (let column = 0; column < 9; column++) {
    result.push(Array.from({ length: 9 }, (_, row) =>
      (rowOrigin + row) * canvasSize + columnOrigin + column,
    ));
  }
  for (let box = 0; box < 9; box++) {
    const boxRow = Math.floor(box / 3) * 3;
    const boxColumn = (box % 3) * 3;
    result.push(Array.from({ length: 9 }, (_, offset) => {
      const row = Math.floor(offset / 3);
      const column = offset % 3;
      return (rowOrigin + boxRow + row) * canvasSize + columnOrigin + boxColumn + column;
    }));
  }
  return result;
});

const unitsByCell = Array.from({ length: canvasSize * canvasSize }, () => [] as number[]);
units.forEach((unit, unitIndex) => {
  unit.forEach((cellIndex) => unitsByCell[cellIndex].push(unitIndex));
});
const activeIndexes = unitsByCell
  .map((memberships, index) => memberships.length === 0 ? -1 : index)
  .filter((index) => index >= 0);

function countSolutions(input: number[], limit = 2): number {
  const board = [...input];
  const masks = Array.from({ length: units.length }, () => 0);
  for (const index of activeIndexes) {
    const value = board[index];
    if (value === 0) continue;
    if (value < 1 || value > 9) return 0;
    const bit = 1 << (value - 1);
    for (const unitIndex of unitsByCell[index]) {
      if ((masks[unitIndex] & bit) !== 0) return 0;
      masks[unitIndex] |= bit;
    }
  }

  let solutions = 0;
  const search = (): void => {
    if (solutions >= limit) return;
    let selectedIndex = -1;
    let selectedMask = 0;
    let selectedCount = 10;
    for (const index of activeIndexes) {
      if (board[index] !== 0) continue;
      let used = 0;
      for (const unitIndex of unitsByCell[index]) used |= masks[unitIndex];
      const available = 0x1ff & ~used;
      const count = bitCount(available);
      if (count === 0) return;
      if (count < selectedCount) {
        selectedIndex = index;
        selectedMask = available;
        selectedCount = count;
        if (count === 1) break;
      }
    }
    if (selectedIndex === -1) {
      solutions++;
      return;
    }
    let available = selectedMask;
    while (available !== 0 && solutions < limit) {
      const bit = available & -available;
      available &= ~bit;
      board[selectedIndex] = Math.log2(bit) + 1;
      for (const unitIndex of unitsByCell[selectedIndex]) masks[unitIndex] |= bit;
      search();
      for (const unitIndex of unitsByCell[selectedIndex]) masks[unitIndex] ^= bit;
      board[selectedIndex] = 0;
    }
  };
  search();
  return solutions;
}

function bitCount(value: number): number {
  let count = 0;
  let remaining = value;
  while (remaining !== 0) {
    remaining &= remaining - 1;
    count++;
  }
  return count;
}

function expectValidSamurai(difficulty: DuelDifficulty): void {
  const puzzle = selectRankedPuzzle(
    difficulty,
    new Uint8Array(Array.from({ length: 16 }, (_, index) => index + 1)),
    'samurai',
  );
  expect(puzzle.puzzle).toHaveLength(441);
  expect(puzzle.solution).toHaveLength(441);
  expect(activeIndexes).toHaveLength(369);
  expect(puzzle.solution.filter((value) => value === -1)).toHaveLength(72);
  expect(puzzle.puzzle.filter((value) => value > 0)).toHaveLength(puzzle.clueCount);
  for (let index = 0; index < 441; index++) {
    if (unitsByCell[index].length === 0) {
      expect(puzzle.puzzle[index]).toBe(-1);
      expect(puzzle.solution[index]).toBe(-1);
    } else {
      expect(puzzle.solution[index]).toBeGreaterThanOrEqual(1);
      expect(puzzle.solution[index]).toBeLessThanOrEqual(9);
      if (puzzle.puzzle[index] !== 0) {
        expect(puzzle.puzzle[index]).toBe(puzzle.solution[index]);
      }
    }
  }
  for (const unit of units) {
    expect(new Set(unit.map((index) => puzzle.solution[index])).size).toBe(9);
  }
  expect(countSolutions(puzzle.puzzle)).toBe(1);
}

describe('variant-aware ranked puzzle bank', () => {
  it.each<DuelDifficulty>(['beginner', 'easy', 'medium', 'hard', 'expert'])(
    'provides a valid unique %s Samurai puzzle',
    expectValidSamurai,
  );

  it('preserves the classic 81-cell bank by default', () => {
    const puzzle = selectRankedPuzzle('easy', new Uint8Array(16));
    expect(puzzle.puzzle).toHaveLength(81);
    expect(puzzle.solution).toHaveLength(81);
    expect(puzzle.puzzle).not.toContain(-1);
  });

  it('changes Samurai digits while preserving the inactive mask', () => {
    const first = selectRankedPuzzle('easy', new Uint8Array(16), 'samurai');
    const secondSeed = new Uint8Array(16);
    secondSeed[0] = 9;
    const second = selectRankedPuzzle('easy', secondSeed, 'samurai');
    expect(second.puzzle).not.toEqual(first.puzzle);
    expect(
      second.puzzle.map((value) => value === -1),
    ).toEqual(first.puzzle.map((value) => value === -1));
  });
});
