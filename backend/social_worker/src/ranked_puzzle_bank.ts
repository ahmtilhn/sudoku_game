import { RANKED_PUZZLES } from './ranked_puzzles';
import { SAMURAI_RANKED_PUZZLES } from './samurai_ranked_puzzles';
import type { DuelDifficulty } from './online_duel';
import {
  duelVariantConfig,
  type DuelVariant,
} from './sudoku_variant';

export type RankedPuzzle = {
  id: string;
  difficulty: string;
  variant?: DuelVariant;
  boardSize?: number;
  cellCount?: number;
  puzzle: number[];
  solution: number[];
  clueCount: number;
  fingerprint: string;
  generationVersion: string;
};

export type RankedPuzzleVariant = 'classic' | 'samurai';

export function selectRankedPuzzle(
  difficulty: DuelDifficulty,
  randomBytes: Uint8Array,
  variant: RankedPuzzleVariant = 'classic',
): RankedPuzzle {
  const bank = variant === 'samurai'
    ? SAMURAI_RANKED_PUZZLES[difficulty] ?? []
    : RANKED_PUZZLES[difficulty] ?? [];
  if (bank.length === 0) {
    throw new Error(`No ${variant} ranked puzzle bank for ${difficulty}`);
  }
  const seed = randomBytes.reduce((acc, value, index) => acc + value * (index + 1), 0);
  const base = bank[seed % bank.length];
  return variant === 'samurai'
    ? transformSamuraiPuzzle(base, seed)
    : transformClassicPuzzle(base, seed);
}

function transformClassicPuzzle(base: RankedPuzzle, seed: number): RankedPuzzle {
  const digits = shuffled([1, 2, 3, 4, 5, 6, 7, 8, 9], seed + 11);
  const rowBands = shuffled([0, 1, 2], seed + 17);
  const colStacks = shuffled([0, 1, 2], seed + 23);
  const rows = rowBands.flatMap((band) =>
    shuffled(
      Array.from({ length: boxSize }, (_, index) => index),
      seed + 31 + band,
    ).map((offset) => band * boxSize + offset),
  );
  const columns = colStacks.flatMap((stack) =>
    shuffled(
      Array.from({ length: boxSize }, (_, index) => index),
      seed + 41 + stack,
    ).map((offset) => stack * boxSize + offset),
  );
  const transpose = seed % 2 === 0;
  const mapCell = (board: number[], row: number, column: number): number => {
    const sourceRow = transpose ? columns[column] : rows[row];
    const sourceColumn = transpose ? rows[row] : columns[column];
    const value = board[sourceRow * size + sourceColumn];
    return value === 0 ? 0 : digits[value - 1];
  };
  const puzzle = Array.from({ length: base.cellCount }, (_, index) =>
    mapCell(base.puzzle, Math.floor(index / size), index % size),
  );
  const solution = Array.from({ length: base.cellCount }, (_, index) =>
    mapCell(base.solution, Math.floor(index / size), index % size),
  );
  return transformed(base, seed, puzzle, solution);
}

function transformSamuraiPuzzle(base: RankedPuzzle, seed: number): RankedPuzzle {
  const digits = shuffled([1, 2, 3, 4, 5, 6, 7, 8, 9], seed + 71);
  const remap = (value: number): number => value > 0 ? digits[value - 1] : value;
  return transformed(
    base,
    seed,
    base.puzzle.map(remap),
    base.solution.map(remap),
  );
}

function transformed(
  base: RankedPuzzle,
  seed: number,
  puzzle: number[],
  solution: number[],
): RankedPuzzle {
  return {
    ...base,
    id: `${base.id}-v${seed}`,
    puzzle,
    solution,
    clueCount: puzzle.filter((value) => value !== 0).length,
    fingerprint: `${base.fingerprint}-${seed.toString(36)}`,
  };
}

function shuffled<T>(values: T[], seed: number): T[] {
  const result = [...values];
  let state = seed || 1;
  for (let index = result.length - 1; index > 0; index--) {
    state = (state * 1664525 + 1013904223) >>> 0;
    const swap = state % (index + 1);
    [result[index], result[swap]] = [result[swap], result[index]];
  }
  return result;
}
