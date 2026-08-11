import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const difficulties = ['beginner', 'easy', 'medium', 'hard', 'expert'] as const;
const clueRanges = {
  beginner: [40, 45],
  easy: [36, 39],
  medium: [32, 35],
  hard: [28, 31],
  expert: [24, 27],
} as const;

type Puzzle = {
  id: string;
  difficulty: string;
  puzzle: number[];
  solution: number[];
  clueCount: number;
  fingerprint: string;
  generationVersion: string;
};

const root = join(process.cwd(), 'src', 'ranked_puzzles');
const report: string[] = ['# Ranked Puzzle Bank Report', ''];
let total = 0;
const fingerprints = new Set<string>();

for (const difficulty of difficulties) {
  const path = join(root, `${difficulty}.json`);
  const entries = JSON.parse(readFileSync(path, 'utf8')) as Puzzle[];
  if (entries.length < 20) fail(`${difficulty} has ${entries.length} puzzles`);
  const clues = entries.map((entry) => validate(entry, difficulty));
  total += entries.length;
  const min = Math.min(...clues);
  const max = Math.max(...clues);
  const average = clues.reduce((sum, value) => sum + value, 0) / clues.length;
  report.push(`## ${difficulty}`);
  report.push('');
  report.push(`- Count: ${entries.length}`);
  report.push(`- Clues: min ${min}, max ${max}, average ${average.toFixed(1)}`);
  report.push(`- Uniqueness: passed`);
  report.push(`- Generation version: curated-v1`);
  report.push('');
}

report.push(`Total puzzles: ${total}`);
report.push('');
report.push('Security boundary: solution grids are bundled only in the Worker backend and are never returned in public snapshots.');
writeFileSync(join(process.cwd(), '..', '..', 'docs', 'RANKED_PUZZLE_BANK_REPORT.md'), `${report.join('\n')}\n`);
console.log(`Verified ${total} ranked backend-only puzzles.`);

function validate(entry: Puzzle, difficulty: string): number {
  if (entry.difficulty !== difficulty) fail(`${entry.id} has wrong difficulty`);
  if (entry.puzzle.length !== 81 || entry.solution.length !== 81) fail(`${entry.id} has wrong length`);
  if (!entry.puzzle.every((value) => Number.isInteger(value) && value >= 0 && value <= 9)) {
    fail(`${entry.id} has invalid puzzle values`);
  }
  if (!entry.solution.every((value) => Number.isInteger(value) && value >= 1 && value <= 9)) {
    fail(`${entry.id} has invalid solution values`);
  }
  if (!validSolved(entry.solution)) fail(`${entry.id} solution is invalid`);
  for (let index = 0; index < 81; index++) {
    if (entry.puzzle[index] !== 0 && entry.puzzle[index] !== entry.solution[index]) {
      fail(`${entry.id} clue mismatch`);
    }
  }
  const clueCount = entry.puzzle.filter((value) => value !== 0).length;
  const [min, max] = clueRanges[difficulty as keyof typeof clueRanges];
  if (clueCount !== entry.clueCount || clueCount < min || clueCount > max) {
    fail(`${entry.id} clue count ${clueCount} outside ${min}-${max}`);
  }
  if (fingerprints.has(entry.fingerprint)) fail(`${entry.id} duplicate fingerprint`);
  fingerprints.add(entry.fingerprint);
  if (countSolutions([...entry.puzzle], 2) !== 1) fail(`${entry.id} is not unique`);
  return clueCount;
}

function validSolved(board: number[]): boolean {
  const target = '123456789';
  for (let row = 0; row < 9; row++) {
    if ([...Array(9)].map((_, col) => board[row * 9 + col]).sort().join('') !== target) return false;
  }
  for (let col = 0; col < 9; col++) {
    if ([...Array(9)].map((_, row) => board[row * 9 + col]).sort().join('') !== target) return false;
  }
  for (let boxRow = 0; boxRow < 3; boxRow++) {
    for (let boxCol = 0; boxCol < 3; boxCol++) {
      const values: number[] = [];
      for (let row = 0; row < 3; row++) for (let col = 0; col < 3; col++) values.push(board[(boxRow * 3 + row) * 9 + boxCol * 3 + col]);
      if (values.sort().join('') !== target) return false;
    }
  }
  return true;
}

function countSolutions(board: number[], limit: number): number {
  let best = -1;
  let candidates: number[] = [];
  for (let index = 0; index < 81; index++) {
    if (board[index] !== 0) continue;
    const legal = legalValues(board, index);
    if (legal.length === 0) return 0;
    if (best === -1 || legal.length < candidates.length) {
      best = index;
      candidates = legal;
    }
  }
  if (best === -1) return 1;
  let count = 0;
  for (const value of candidates) {
    board[best] = value;
    count += countSolutions(board, limit);
    board[best] = 0;
    if (count >= limit) return count;
  }
  return count;
}

function legalValues(board: number[], index: number): number[] {
  const used = new Set<number>();
  const row = Math.floor(index / 9);
  const column = index % 9;
  for (let cursor = 0; cursor < 9; cursor++) {
    used.add(board[row * 9 + cursor]);
    used.add(board[cursor * 9 + column]);
  }
  const boxRow = Math.floor(row / 3) * 3;
  const boxCol = Math.floor(column / 3) * 3;
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) used.add(board[(boxRow + r) * 9 + boxCol + c]);
  return [1, 2, 3, 4, 5, 6, 7, 8, 9].filter((value) => !used.has(value));
}

function fail(message: string): never {
  throw new Error(message);
}
