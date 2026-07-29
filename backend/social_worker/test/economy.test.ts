import { describe, expect, it } from 'vitest';

import {
  CAREER_AD_REWARD,
  COIN_PRODUCTS,
  DAILY_AD_REWARD,
  DAILY_LOGIN_REWARD,
  ENTRY_FEES,
  MATCH_ENTRY_FEE,
  MATCH_POT,
  NO_ADS_PRODUCT_ID,
  REMATCH_WINDOW_MS,
  STARTER_COINS,
  entryFeeForDifficulty,
  potForDifficulty,
} from '../src/economy';

describe('online Coin economy defaults', () => {
  it('keeps the entry fee and winner pot balanced', () => {
    expect(MATCH_ENTRY_FEE).toBe(100);
    expect(MATCH_POT).toBe(MATCH_ENTRY_FEE * 2);
    expect(ENTRY_FEES).toEqual({
      beginner: 100,
      easy: 150,
      medium: 250,
      hard: 400,
      expert: 650,
    });
    expect(entryFeeForDifficulty('expert')).toBe(650);
    expect(potForDifficulty('expert')).toBe(1300);
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
    expect(COIN_PRODUCTS).not.toHaveProperty(NO_ADS_PRODUCT_ID);
    expect(NO_ADS_PRODUCT_ID).toBe('no_ads');
  });
});
