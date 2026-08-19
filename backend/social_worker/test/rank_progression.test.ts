import { describe, expect, it } from 'vitest';

import {
  RANK_TIERS,
  TOTAL_LIFETIME_RANK_REWARD,
  applyPercent,
  baseRankDelta,
  encodeIdentityAvatarKey,
  pointsProgress,
  rankAlignmentPercent,
  repeatGainPercent,
  tierForPoints,
} from '../src/rank_progression';

describe('visible rank progression', () => {
  it('starts at Bronze III and advances every 300 RP through Master I', () => {
    expect(tierForPoints(0).key).toBe('bronze_3');
    expect(tierForPoints(299).key).toBe('bronze_3');
    expect(tierForPoints(300).key).toBe('bronze_2');
    expect(tierForPoints(600).key).toBe('bronze_1');
    expect(tierForPoints(900).key).toBe('silver_3');
    expect(tierForPoints(1800).key).toBe('gold_3');
    expect(tierForPoints(2700).key).toBe('platinum_3');
    expect(tierForPoints(3600).key).toBe('master_3');
    expect(tierForPoints(3900).key).toBe('master_2');
    expect(tierForPoints(4200).key).toBe('master_1');
    expect(tierForPoints(999999).key).toBe('master_1');
    expect(RANK_TIERS).toHaveLength(15);
  });

  it('distributes exactly 12,000 lifetime rank Coins', () => {
    expect(TOTAL_LIFETIME_RANK_REWARD).toBe(12000);
  });

  it('uses the agreed opponent-strength RP table', () => {
    expect(baseRankDelta(1000, 700, 'win')).toBe(10);
    expect(baseRankDelta(1000, 700, 'draw')).toBe(-15);
    expect(baseRankDelta(1000, 700, 'loss')).toBe(-40);

    expect(baseRankDelta(1000, 1000, 'win')).toBe(24);
    expect(baseRankDelta(1000, 1000, 'draw')).toBe(0);
    expect(baseRankDelta(1000, 1000, 'loss')).toBe(-24);

    expect(baseRankDelta(1000, 1300, 'win')).toBe(40);
    expect(baseRankDelta(1000, 1300, 'draw')).toBe(15);
    expect(baseRankDelta(1000, 1300, 'loss')).toBe(-10);
  });

  it('accelerates catch-up when MMR is above visible rank', () => {
    expect(rankAlignmentPercent(24, 1500, 1000)).toBe(125);
    expect(rankAlignmentPercent(-24, 1500, 1000)).toBe(75);
    expect(applyPercent(24, 125)).toBe(30);
    expect(applyPercent(-24, 75)).toBe(-18);
  });

  it('pushes an overrated visible rank back toward MMR', () => {
    expect(rankAlignmentPercent(24, 1000, 1500)).toBe(75);
    expect(rankAlignmentPercent(-24, 1000, 1500)).toBe(125);
    expect(applyPercent(24, 75)).toBe(18);
    expect(applyPercent(-24, 125)).toBe(-30);
  });

  it('limits positive repeat-opponent farming after two full-value games', () => {
    expect(repeatGainPercent(0)).toBe(100);
    expect(repeatGainPercent(1)).toBe(100);
    expect(repeatGainPercent(2)).toBe(50);
    expect(repeatGainPercent(3)).toBe(0);
    expect(repeatGainPercent(20)).toBe(0);
  });

  it('reports progress to the next 300-point division', () => {
    expect(pointsProgress(0)).toEqual({
      pointsInDivision: 0,
      divisionSize: 300,
      pointsToNext: 300,
      progress: 0,
    });
    expect(pointsProgress(150).progress).toBe(0.5);
    expect(pointsProgress(299).pointsToNext).toBe(1);
    expect(pointsProgress(4200).pointsToNext).toBeNull();
  });

  it('encodes an identity into the existing avatar key without protocol changes', () => {
    expect(
      encodeIdentityAvatarKey('preset_007', 'gold_2', [
        'unbeaten_shield_50',
        'perfect_star',
      ]),
    ).toBe('idv1|preset_007|gold_2|unbeaten_shield_50,perfect_star');
  });
});
