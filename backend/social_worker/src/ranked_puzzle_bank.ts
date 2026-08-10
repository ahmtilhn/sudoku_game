import { RANKED_PUZZLES } from './ranked_puzzles';
import { SAMURAI_RANKED_PUZZLES } from './samurai_ranked_puzzles';
import type { DuelDifficulty } from './online_duel_model';
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

export type RankedPuzzleVariant = DuelVariant | 'classic';

export function selectRankedPuzzle(
  difficulty: DuelDifficulty,
  randomBytes: Uint8Array,
  variant: RankedPuzzleVariant = 'classic',
): RankedPuzzle {
  const normalizedVariant = variant === 'classic' ? 'classic9' : variant;
  if (normalizedVariant === 'classic16') {
    return transformClassic16Puzzle(difficulty, randomBytes);
  }
  const bank = normalizedVariant === 'samurai'
    ? SAMURAI_RANKED_PUZZLES[difficulty] ?? []
    : RANKED_PUZZLES[difficulty] ?? [];
  if (bank.length === 0) {
    throw new Error(`No ${normalizedVariant} ranked puzzle bank for ${difficulty}`);
  }
  const seed = randomBytes.reduce((acc, value, index) => acc + value * (index + 1), 0);
  const base = bank[seed % bank.length];
  return normalizedVariant === 'samurai'
    ? transformSamuraiPuzzle(base, seed)
    : transformClassicPuzzle(base, seed);
}

function transformClassicPuzzle(base: RankedPuzzle, seed: number): RankedPuzzle {
  const size = 9;
  const boxSize = 3;
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
  const cellCount = base.cellCount ?? base.puzzle.length;
  const puzzle = Array.from({ length: cellCount }, (_, index) =>
    mapCell(base.puzzle, Math.floor(index / size), index % size),
  );
  const solution = Array.from({ length: cellCount }, (_, index) =>
    mapCell(base.solution, Math.floor(index / size), index % size),
  );
  return transformed(base, seed, puzzle, solution);
}

function transformClassic16Puzzle(
  difficulty: DuelDifficulty,
  randomBytes: Uint8Array,
): RankedPuzzle {
  const size = 16;
  const boxRows = 4;
  const boxColumns = 4;
  const seed = randomBytes.reduce((acc, value, index) => acc + value * (index + 1), 0);
  const digits = shuffled(
    Array.from({ length: size }, (_, index) => index + 1),
    seed + 101,
  );
  const solution = Array.from({ length: size * size }, (_, index) => {
    const row = Math.floor(index / size);
    const column = index % size;
    const baseValue = (row * boxColumns + Math.floor(row / boxRows) + column) % size;
    return digits[baseValue];
  });
  const clueTarget = clueTargetFor16(difficulty);
  const puzzle = [...solution];
  for (const index of shuffled(
    Array.from({ length: size * size }, (_, cell) => cell),
    seed + 131,
  ).slice(0, size * size - clueTarget)) {
    puzzle[index] = 0;
  }
  return {
    id: `classic16-${difficulty}-${seed.toString(36)}`,
    difficulty,
    variant: 'classic16',
    boardSize: 16,
    cellCount: 256,
    puzzle,
    solution,
    clueCount: puzzle.filter((value) => value > 0).length,
    fingerprint: `classic16-${difficulty}-${seed.toString(36)}`,
    generationVersion: 'generated-16x16-v1',
  };
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
    boardSize: base.boardSize ?? duelVariantConfig(base.variant ?? 'classic9').boardSize,
    cellCount: puzzle.length,
    clueCount: puzzle.filter((value) => value > 0).length,
    fingerprint: `${base.fingerprint}-${seed.toString(36)}`,
  };
}

function clueTargetFor16(difficulty: DuelDifficulty): number {
  switch (difficulty) {
    case 'beginner':
      return 120;
    case 'easy':
      return 104;
    case 'medium':
      return 88;
    case 'hard':
      return 72;
    case 'expert':
      return 60;
  }
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
