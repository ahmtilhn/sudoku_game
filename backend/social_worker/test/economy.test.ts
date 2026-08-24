import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

import {
  CAREER_AD_REWARD,
  COIN_PRODUCTS,
  DAILY_AD_REWARD,
  DAILY_LOGIN_REWARD,
  ENTRY_FEES,
  IOS_NO_ADS_PRODUCT_ID,
  MATCH_ENTRY_FEE,
  MATCH_POT,
  NO_ADS_PRODUCT_ID,
  REMATCH_WINDOW_MS,
  STARTER_COINS,
  entryFeeForDifficulty,
  isNoAdsProductId,
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
    expect(COIN_PRODUCTS).not.toHaveProperty(IOS_NO_ADS_PRODUCT_ID);
    expect(NO_ADS_PRODUCT_ID).toBe('no_ads');
    expect(IOS_NO_ADS_PRODUCT_ID).toBe('sudoku_duel_no_ads');
    expect(isNoAdsProductId(NO_ADS_PRODUCT_ID)).toBe(true);
    expect(isNoAdsProductId(IOS_NO_ADS_PRODUCT_ID)).toBe(true);
    expect(isNoAdsProductId('coins_100')).toBe(false);
  });

  it('keeps debug unlimited coins aligned with the ledger invariant', () => {
    const testDir = fileURLToPath(new URL('.', import.meta.url));
    const source = readFileSync(resolve(testDir, '../src/economy.ts'), 'utf8');

    expect(source).toContain('DEBUG_UNLIMITED_COINS_BALANCE');
    expect(source).toContain('targetBalance - currentBalance');
    expect(source).toContain("'admin_adjustment', 'debug'");
    expect(source).toContain('debug_unlimited:');
  });
});
