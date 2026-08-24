import { readFileSync } from 'node:fs';
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
  it('keeps unplayed accounts out while showing every ranked player', () => {
    const source = readFileSync('src/rank_progression.ts', 'utf8');

    expect(source).toContain('WHERE rp.ranked_games > 0');
    expect(source).not.toContain('COALESCE(p.discoverable, 1)');
  });

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
    RANK_TIERS.forEach((tier, index) => {
      expect(tier.minPoints).toBe(index * 300);
    });
  });

  it('distributes exactly the agreed 12,000 lifetime rank Coins', () => {
    expect(TOTAL_LIFETIME_RANK_REWARD).toBe(12000);
    expect(
      Object.fromEntries(RANK_TIERS.map((tier) => [tier.key, tier.rewardCoins])),
    ).toEqual({
      bronze_3: 0,
      bronze_2: 250,
      bronze_1: 350,
      silver_3: 600,
      silver_2: 450,
      silver_1: 550,
      gold_3: 900,
      gold_2: 650,
      gold_1: 750,
      platinum_3: 1200,
      platinum_2: 850,
      platinum_1: 950,
      master_3: 1500,
      master_2: 1200,
      master_1: 1800,
    });
  });

  it('uses the agreed opponent-strength RP table including boundaries', () => {
    const cases = [
      [-400, 10, -15, -40],
      [-251, 10, -15, -40],
      [-250, 12, -12, -36],
      [-151, 12, -12, -36],
      [-150, 18, -6, -30],
      [-76, 18, -6, -30],
      [-75, 24, 0, -24],
      [0, 24, 0, -24],
      [75, 24, 0, -24],
      [76, 30, 6, -18],
      [150, 30, 6, -18],
      [151, 36, 12, -12],
      [250, 36, 12, -12],
      [251, 40, 15, -10],
      [400, 40, 15, -10],
    ] as const;

    for (const [difference, win, draw, loss] of cases) {
      const player = 1500;
      const opponent = player + difference;
      expect(baseRankDelta(player, opponent, 'win')).toBe(win);
      expect(baseRankDelta(player, opponent, 'draw')).toBe(draw);
      expect(baseRankDelta(player, opponent, 'loss')).toBe(loss);
    }
  });

  it('accelerates catch-up when MMR is above visible rank', () => {
    expect(rankAlignmentPercent(24, 1500, 1000)).toBe(125);
    expect(rankAlignmentPercent(-24, 1500, 1000)).toBe(75);
    expect(applyPercent(24, 125)).toBe(30);
    expect(applyPercent(-24, 75)).toBe(-18);
  });

  it('uses exact catch-up modifier boundaries', () => {
    expect(rankAlignmentPercent(24, 1099, 1000)).toBe(100);
    expect(rankAlignmentPercent(24, 1100, 1000)).toBe(110);
    expect(rankAlignmentPercent(24, 1199, 1000)).toBe(110);
    expect(rankAlignmentPercent(24, 1200, 1000)).toBe(125);
    expect(rankAlignmentPercent(-24, 1099, 1000)).toBe(100);
    expect(rankAlignmentPercent(-24, 1100, 1000)).toBe(90);
    expect(rankAlignmentPercent(-24, 1200, 1000)).toBe(75);
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

  it('encodes at most three identity decorations into the existing avatar key', () => {
    expect(
      encodeIdentityAvatarKey('preset_007', 'gold_2', [
        'unbeaten_shield_50',
        'perfect_star',
        'giant_slayer',
        'veteran_1000',
      ]),
    ).toBe(
      'idv1|preset_007|gold_2|unbeaten_shield_50,perfect_star,giant_slayer',
    );
  });
});
