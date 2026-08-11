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

  it('locks Career rewards and daily budget', () => {
    expect(CAREER_REWARDS).toEqual({
      beginner: 20,
      easy: 25,
      medium: 35,
      hard: 40,
      expert: 50,
    });
    expect(CAREER_DAILY_COIN_CAP).toBe(250);
    expect(careerDifficulty(1, 'classic9')).toBe('beginner');
    expect(careerDifficulty(41, 'classic9')).toBe('expert');
    expect(careerDifficulty(999, 'classic9')).toBe('expert');
    expect(careerDifficulty(17, 'classic16')).toBe('expert');
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
