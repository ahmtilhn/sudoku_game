#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const target = resolve('backend/social_worker/src/samurai_ranked_puzzles.ts');
const source = readFileSync(target, 'utf8');
const entryPattern = /(beginner|easy|medium|hard|expert):\[\{id:'([^']+)',difficulty:'([^']+)',puzzle:\[([^\]]*)\],solution:\[[^\]]*\],clueCount:(\d+),fingerprint:'([^']+)',generationVersion:'([^']+)'\}\]/g;
const entries = [];
for (const match of source.matchAll(entryPattern)) {
  const [, key, id, difficulty, puzzleText, clueCount, fingerprint, generationVersion] = match;
  const puzzle = puzzleText.split(',').map((value) => Number.parseInt(value, 10));
  if (puzzle.length !== 441 || puzzle.some((value) => !Number.isInteger(value))) {
    throw new Error(`${key} puzzle has invalid shape: ${puzzle.length}`);
  }
  const solution = solveSamurai(puzzle);
  entries.push({ key, id, difficulty, puzzle, solution, clueCount: Number(clueCount), fingerprint, generationVersion });
}
if (entries.length !== 5) {
  throw new Error(`Expected five Samurai entries, found ${entries.length}`);
}

const lines = [
  'export type SamuraiRankedPuzzle = {',
  '  id: string;',
  '  difficulty: string;',
  '  puzzle: number[];',
  '  solution: number[];',
  '  clueCount: number;',
  '  fingerprint: string;',
  '  generationVersion: string;',
  '};',
  '',
  'export const SAMURAI_RANKED_PUZZLES: Record<string, SamuraiRankedPuzzle[]> = {',
];
for (const entry of entries) {
  lines.push(`  ${entry.key}: [{`);
  lines.push(`    id: '${entry.id}',`);
  lines.push(`    difficulty: '${entry.difficulty}',`);
  lines.push(`    puzzle: [${entry.puzzle.join(',')}],`);
  lines.push(`    solution: [${entry.solution.join(',')}],`);
  lines.push(`    clueCount: ${entry.clueCount},`);
  lines.push(`    fingerprint: '${entry.fingerprint}',`);
  lines.push(`    generationVersion: '${entry.generationVersion}',`);
  lines.push('  }],');
}
lines.push('};', '');
writeFileSync(target, lines.join('\n'), 'utf8');
console.log('Rebuilt five 441-cell Samurai solutions from their unique puzzles.');

function solveSamurai(input) {
  const board = [...input];
  const { units, unitsByCell, activeIndexes } = topology();
  const masks = Array.from({ length: units.length }, () => 0);
  for (let index = 0; index < board.length; index++) {
    if (unitsByCell[index].length === 0) {
      if (board[index] !== -1) throw new Error(`Inactive cell ${index} is not -1.`);
      continue;
    }
    const value = board[index];
    if (value === 0) continue;
    if (value < 1 || value > 9) throw new Error(`Invalid clue at ${index}.`);
    const bit = 1 << (value - 1);
    for (const unitIndex of unitsByCell[index]) {
      if ((masks[unitIndex] & bit) !== 0) throw new Error(`Conflicting clue at ${index}.`);
      masks[unitIndex] |= bit;
    }
  }

  let solutionCount = 0;
  let firstSolution = null;
  const search = () => {
    if (solutionCount >= 2) return;
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
      solutionCount++;
      firstSolution ??= [...board];
      return;
    }
    let available = selectedMask;
    while (available !== 0 && solutionCount < 2) {
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
  if (solutionCount !== 1 || firstSolution === null) {
    throw new Error(`Expected unique Samurai solution, found ${solutionCount}.`);
  }
  return firstSolution;
}

function topology() {
  const canvasSize = 21;
  const origins = [[0, 0], [0, 12], [6, 6], [12, 0], [12, 12]];
  const units = [];
  for (const [rowOrigin, columnOrigin] of origins) {
    for (let row = 0; row < 9; row++) {
      units.push(Array.from({ length: 9 }, (_, column) =>
        (rowOrigin + row) * canvasSize + columnOrigin + column));
    }
    for (let column = 0; column < 9; column++) {
      units.push(Array.from({ length: 9 }, (_, row) =>
        (rowOrigin + row) * canvasSize + columnOrigin + column));
    }
    for (let box = 0; box < 9; box++) {
      const boxRow = Math.floor(box / 3) * 3;
      const boxColumn = (box % 3) * 3;
      units.push(Array.from({ length: 9 }, (_, offset) => {
        const row = Math.floor(offset / 3);
        const column = offset % 3;
        return (rowOrigin + boxRow + row) * canvasSize + columnOrigin + boxColumn + column;
      }));
    }
  }
  const unitsByCell = Array.from({ length: 441 }, () => []);
  units.forEach((unit, unitIndex) => {
    unit.forEach((cellIndex) => unitsByCell[cellIndex].push(unitIndex));
  });
  const activeIndexes = unitsByCell
    .map((memberships, index) => memberships.length === 0 ? -1 : index)
    .filter((index) => index >= 0);
  return { units, unitsByCell, activeIndexes };
}

function bitCount(value) {
  let count = 0;
  let remaining = value;
  while (remaining !== 0) {
    remaining &= remaining - 1;
    count++;
  }
  return count;
}
