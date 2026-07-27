import { describe, expect, it } from 'vitest';

import {
  CAREER_AD_REWARD,
  COIN_PRODUCTS,
  DAILY_AD_REWARD,
  DAILY_LOGIN_REWARD,
  MATCH_ENTRY_FEE,
  MATCH_POT,
  REMATCH_WINDOW_MS,
  STARTER_COINS,
} from '../src/economy';

describe('online Coin economy defaults', () => {
  it('keeps the entry fee and winner pot balanced', () => {
    expect(MATCH_ENTRY_FEE).toBe(100);
    expect(MATCH_POT).toBe(MATCH_ENTRY_FEE * 2);
  });

  it('keeps starter and daily rewards at the product defaults', () => {
    expect(STARTER_COINS).toBe(1000);
    expect(DAILY_LOGIN_REWARD).toBe(50);
    expect(DAILY_AD_REWARD).toBe(50);
    expect(CAREER_AD_REWARD).toBe(25);
  });

  it('uses a ten second rematch window', () => {
    expect(REMATCH_WINDOW_MS).toBe(10_000);
  });

  it('contains the complete consumable product ladder', () => {
    expect(COIN_PRODUCTS).toEqual({
      coins_100: 100,
      coins_500: 500,
      coins_1000: 1000,
      coins_5000: 5000,
      coins_10000: 10000,
      coins_50000: 50000,
      coins_100000: 100000,
    });
  });
});
