export type DuelVariant = 'classic9' | 'classic16' | 'samurai';

export type DuelVariantConfig = {
  variant: DuelVariant;
  boardSize: 9 | 16 | 21;
  boxRows: 3 | 4;
  boxColumns: 3 | 4;
  cellCount: 81 | 256 | 441;
};

export const DUEL_VARIANTS: Readonly<Record<DuelVariant, DuelVariantConfig>> =
  Object.freeze({
    classic9: Object.freeze({
      variant: 'classic9',
      boardSize: 9,
      boxRows: 3,
      boxColumns: 3,
      cellCount: 81,
    }),
    classic16: Object.freeze({
      variant: 'classic16',
      boardSize: 16,
      boxRows: 4,
      boxColumns: 4,
      cellCount: 256,
    }),
    samurai: Object.freeze({
      variant: 'samurai',
      boardSize: 21,
      boxRows: 3,
      boxColumns: 3,
      cellCount: 441,
    }),
  });

export function normalizeDuelVariant(
  value: unknown,
  fallback: DuelVariant = 'classic9',
): DuelVariant {
  if (value == null || value === '') return fallback;
  if (value === 'classic') return 'classic9';
  if (value === 'classic9' || value === 'classic16') return value;
  if (value === 'samurai') return value;
  throw new Error('Invalid Sudoku variant.');
}

export function duelVariantConfig(variant: DuelVariant): DuelVariantConfig {
  return DUEL_VARIANTS[variant];
}

export function inferDuelVariant(cellCount: number): DuelVariant {
  if (cellCount === DUEL_VARIANTS.classic9.cellCount) return 'classic9';
  if (cellCount === DUEL_VARIANTS.classic16.cellCount) return 'classic16';
  if (cellCount === DUEL_VARIANTS.samurai.cellCount) return 'samurai';
  throw new Error(`Unsupported online duel cell count: ${cellCount}.`);
}
