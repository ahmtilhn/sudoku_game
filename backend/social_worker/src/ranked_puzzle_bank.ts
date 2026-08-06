import { RANKED_PUZZLES } from './ranked_puzzles';
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

export type SelectedRankedPuzzle = RankedPuzzle & {
  variant: DuelVariant;
  boardSize: number;
  cellCount: number;
};

export function selectRankedPuzzle(
  difficulty: DuelDifficulty,
  randomBytes: Uint8Array,
  variant: DuelVariant = 'classic9',
): SelectedRankedPuzzle {
  const seed = randomBytes.reduce(
    (acc, value, index) => acc + value * (index + 1),
    0,
  );
  if (variant === 'classic16') {
    return generateClassic16Puzzle(difficulty, seed);
  }

  const bank = RANKED_PUZZLES[difficulty] ?? [];
  if (bank.length === 0) {
    throw new Error(`No ranked puzzle bank for ${difficulty}`);
  }
  const base = bank[seed % bank.length];
  return transformPuzzle(
    {
      ...base,
      variant: 'classic9',
      boardSize: 9,
      cellCount: 81,
    },
    seed,
  );
}

function generateClassic16Puzzle(
  difficulty: DuelDifficulty,
  seed: number,
): SelectedRankedPuzzle {
  const config = duelVariantConfig('classic16');
  const boxSize = config.boxRows;
  const baseSolution = Array.from(
    { length: config.cellCount },
    (_, index) => {
      const row = Math.floor(index / config.boardSize);
      const column = index % config.boardSize;
      return (
        (boxSize * (row % boxSize) + Math.floor(row / boxSize) + column) %
          config.boardSize
      ) + 1;
    },
  );
  const basePuzzle = [...baseSolution];
  const removalPasses: Record<DuelDifficulty, number> = {
    beginner: 4,
    easy: 5,
    medium: 6,
    hard: 7,
    expert: 8,
  };
  for (let pass = 0; pass < removalPasses[difficulty]; pass++) {
    for (let row = 0; row < config.boardSize; row++) {
      const column = (row * 5 + pass * 3) % config.boardSize;
      basePuzzle[row * config.boardSize + column] = 0;
    }
  }

  return transformPuzzle(
    {
      id: `ranked-classic16-${difficulty}`,
      difficulty,
      variant: 'classic16',
      boardSize: config.boardSize,
      cellCount: config.cellCount,
      puzzle: basePuzzle,
      solution: baseSolution,
      clueCount: basePuzzle.filter((value) => value !== 0).length,
      fingerprint: `classic16-${difficulty}`,
      generationVersion: 'classic16-v1',
    },
    seed,
  );
}

function transformPuzzle(
  base: SelectedRankedPuzzle,
  seed: number,
): SelectedRankedPuzzle {
  const size = base.boardSize;
  const boxSize = Math.sqrt(size);
  if (!Number.isInteger(boxSize)) {
    throw new Error(`Unsupported ranked board size: ${size}.`);
  }
  const digits = shuffled(
    Array.from({ length: size }, (_, index) => index + 1),
    seed + 11,
  );
  const rowBands = shuffled(
    Array.from({ length: boxSize }, (_, index) => index),
    seed + 17,
  );
  const colStacks = shuffled(
    Array.from({ length: boxSize }, (_, index) => index),
    seed + 23,
  );
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
