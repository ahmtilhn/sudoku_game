export const CAREER_DAILY_COIN_CAP = 250;
export const RECOVERY_DAILY_COIN_CAP = 150;
export const RECOVERY_DAILY_POPUP_CAP = 3;
export const RECOVERY_COOLDOWN_MS = 2 * 60 * 60 * 1000;
export const HINT_COIN_COST = 25;
export const HINT_REFILL_SIZE = 3;

export type DailyReward =
  | { kind: 'coin'; amount: number }
  | { kind: 'hint_refill'; amount: 1 };

export const DAILY_REWARD_CALENDAR: ReadonlyArray<DailyReward> = Object.freeze([
  { kind: 'coin', amount: 40 },
  { kind: 'coin', amount: 50 },
  { kind: 'coin', amount: 50 },
  { kind: 'hint_refill', amount: 1 },
  { kind: 'coin', amount: 70 },
  { kind: 'coin', amount: 50 },
  { kind: 'coin', amount: 100 },
  { kind: 'coin', amount: 50 },
  { kind: 'coin', amount: 60 },
  { kind: 'hint_refill', amount: 1 },
  { kind: 'coin', amount: 50 },
  { kind: 'coin', amount: 70 },
  { kind: 'coin', amount: 50 },
  { kind: 'coin', amount: 120 },
  { kind: 'hint_refill', amount: 1 },
  { kind: 'coin', amount: 50 },
  { kind: 'coin', amount: 70 },
  { kind: 'coin', amount: 60 },
  { kind: 'hint_refill', amount: 1 },
  { kind: 'coin', amount: 80 },
  { kind: 'coin', amount: 150 },
  { kind: 'coin', amount: 50 },
  { kind: 'coin', amount: 70 },
  { kind: 'coin', amount: 80 },
  { kind: 'hint_refill', amount: 1 },
  { kind: 'coin', amount: 60 },
  { kind: 'coin', amount: 80 },
  { kind: 'coin', amount: 120 },
  { kind: 'hint_refill', amount: 1 },
  { kind: 'coin', amount: 150 },
]);

export const CAREER_REWARDS: Readonly<Record<string, number>> = Object.freeze({
  beginner: 20,
  easy: 25,
  medium: 35,
  hard: 40,
  expert: 50,
});

export function careerDifficulty(level: number, variant: string): string {
  if (variant === 'classic16') {
    const index = Math.min(4, Math.floor((level - 1) / 4));
    return ['beginner', 'easy', 'medium', 'hard', 'expert'][index];
  }
  const index = level > 50 ? 4 : Math.min(4, Math.floor((level - 1) / 10));
  return ['beginner', 'easy', 'medium', 'hard', 'expert'][index];
}

export function careerRewardFor(level: number, variant: string): number {
  return CAREER_REWARDS[careerDifficulty(level, variant)] ?? 20;
}

export function recoveryAmount(entryFee: number, broke: boolean): number {
  if (broke) return 75;
  return Math.max(25, Math.min(75, Math.round(entryFee * 0.10)));
}

export function normalizeVariant(value: unknown): 'classic9' | 'classic16' {
  const raw = String(value ?? 'classic9').toLowerCase();
  if (raw === 'classic9' || raw === 'classic_9' || raw === '9x9') return 'classic9';
  if (raw === 'classic16' || raw === 'classic_16' || raw === '16x16') return 'classic16';
  throw new Error('invalid_variant');
}
