import { describe, expect, it } from 'vitest';

import {
  CAREER_DAILY_COIN_CAP,
  CAREER_REWARDS,
  DAILY_REWARD_CALENDAR,
  RECOVERY_DAILY_COIN_CAP,
  RECOVERY_DAILY_POPUP_CAP,
  careerDifficulty,
  recoveryAmount,
} from '../src/economy_v3_policy';

describe('Economy V3 policy', () => {
  it('keeps the 30-day track at 1,560 Coins and 6 Hint Refills', () => {
    const coins = DAILY_REWARD_CALENDAR.filter(
      (reward) => reward.kind === 'coin',
    ).reduce((sum, reward) => sum + reward.amount, 0);
    const refills = DAILY_REWARD_CALENDAR.filter(
      (reward) => reward.kind === 'hint_refill',
    ).length;

    expect(DAILY_REWARD_CALENDAR).toHaveLength(30);
    expect(DAILY_REWARD_CALENDAR).toEqual([
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 50 },
      { kind: 'hint_refill', amount: 1 },
      { kind: 'coin', amount: 70 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 100 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 70 },
      { kind: 'hint_refill', amount: 1 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 70 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 120 },
      { kind: 'hint_refill', amount: 1 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 70 },
      { kind: 'coin', amount: 50 },
      { kind: 'hint_refill', amount: 1 },
      { kind: 'coin', amount: 70 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 70 },
      { kind: 'coin', amount: 50 },
      { kind: 'hint_refill', amount: 1 },
      { kind: 'coin', amount: 50 },
      { kind: 'coin', amount: 70 },
      { kind: 'coin', amount: 50 },
      { kind: 'hint_refill', amount: 1 },
      { kind: 'coin', amount: 150 },
    ]);
    expect(coins).toBe(1560);
    expect(refills).toBe(6);
    expect(DAILY_REWARD_CALENDAR[29]).toEqual({ kind: 'coin', amount: 150 });
  });

  it('keeps Career level rewards uncapped', () => {
    expect(CAREER_REWARDS).toEqual({
      beginner: 20,
      easy: 25,
      medium: 35,
      hard: 40,
      expert: 50,
    });
    expect(CAREER_DAILY_COIN_CAP).toBeNull();
    expect(careerDifficulty(1, 'classic9')).toBe('beginner');
    expect(careerDifficulty(41, 'classic9')).toBe('expert');
    expect(careerDifficulty(999, 'classic9')).toBe('expert');
    expect(careerDifficulty(17, 'classic16')).toBe('expert');
  });

  it('accepts generated and Career Hub practice puzzles for play rewards', async () => {
    const source = await import('node:fs/promises').then((fs) =>
      fs.readFile('src/economy_v3_play.ts', 'utf8'),
    );

    expect(source).toContain('generated-${input.difficulty}-');
    expect(source).toContain('career-random-${input.difficulty}-');
    expect(source).toContain('classic16-${input.difficulty}-');
  });

  it('keeps hint refills server-authoritative and non-negative', async () => {
    const fs = await import('node:fs/promises');
    const [daily, hints, schema] = await Promise.all([
      fs.readFile('src/economy_v3_daily.ts', 'utf8'),
      fs.readFile('src/economy_v3_career_hints.ts', 'utf8'),
      fs.readFile('src/economy_v3_schema.ts', 'utf8'),
    ]);

    expect(daily).toContain("source: 'daily_calendar_refill'");
    expect(daily).toContain('refillDelta: 1');
    expect(hints).toContain('SET hint_refills = hint_refills - 1');
    expect(hints).toContain('WHERE player_id = ? AND hint_refills > 0');
    expect(schema).toContain('hint_refills = MAX(0, economy_v3_inventory.hint_refills + NEW.refill_delta)');
  });

  it('locks Recovery caps and stake-scaled rewards', () => {
    expect(RECOVERY_DAILY_COIN_CAP).toBe(150);
    expect(RECOVERY_DAILY_POPUP_CAP).toBe(3);
    expect(recoveryAmount(100, false)).toBe(25);
    expect(recoveryAmount(150, false)).toBe(25);
    expect(recoveryAmount(250, false)).toBe(25);
    expect(recoveryAmount(400, false)).toBe(40);
    expect(recoveryAmount(650, false)).toBe(65);
    expect(recoveryAmount(650, true)).toBe(75);
  });
});
