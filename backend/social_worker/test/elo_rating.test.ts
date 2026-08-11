import { describe, expect, it } from 'vitest';

import { applyRating, eloDelta } from '../src/online_duel';

describe('ranked ELO rating system', () => {
  it('uses the expected equal-rating win draw and loss deltas', () => {
    expect(eloDelta(1000, 1000, 1, 0)).toBe(20);
    expect(eloDelta(1000, 1000, 0.5, 0)).toBe(0);
    expect(eloDelta(1000, 1000, 0, 0)).toBe(-20);
  });

  it('switches K-factor after 20 and 100 completed rated games', () => {
    expect(eloDelta(1000, 1000, 1, 19)).toBe(20);
    expect(eloDelta(1000, 1000, 1, 20)).toBe(12);
    expect(eloDelta(1000, 1000, 1, 99)).toBe(12);
    expect(eloDelta(1000, 1000, 1, 100)).toBe(8);
  });

  it('rewards an upset more than an expected win', () => {
    const underdogWin = eloDelta(900, 1400, 1, 20);
    const favoriteWin = eloDelta(1400, 900, 1, 20);

    expect(underdogWin).toBe(23);
    expect(favoriteWin).toBe(1);
    expect(underdogWin).toBeGreaterThan(favoriteWin);
  });

  it('keeps two-player deltas symmetric when both use the same K-factor', () => {
    const winnerDelta = eloDelta(1200, 1000, 1, 0);
    const loserDelta = eloDelta(1000, 1200, 0, 0);
    const strongerDraw = eloDelta(1200, 1000, 0.5, 0);
    const weakerDraw = eloDelta(1000, 1200, 0.5, 0);

    expect(winnerDelta).toBe(10);
    expect(loserDelta).toBe(-10);
    expect(winnerDelta + loserDelta).toBe(0);
    expect(strongerDraw).toBe(-10);
    expect(weakerDraw).toBe(10);
    expect(strongerDraw + weakerDraw).toBe(0);
  });

  it('allows player-specific K-factors without producing invalid values', () => {
    const provisionalWinner = eloDelta(1000, 1000, 1, 0);
    const establishedLoser = eloDelta(1000, 1000, 0, 100);

    expect(provisionalWinner).toBe(20);
    expect(establishedLoser).toBe(-8);
    expect(Number.isFinite(provisionalWinner)).toBe(true);
    expect(Number.isFinite(establishedLoser)).toBe(true);
  });

  it('clamps every applied rating to the supported 100 through 3000 range', () => {
    expect(applyRating(100, -20)).toBe(100);
    expect(applyRating(110, -20)).toBe(100);
    expect(applyRating(2990, 20)).toBe(3000);
    expect(applyRating(3000, 20)).toBe(3000);
    expect(applyRating(1500, 12)).toBe(1512);
  });

  it('produces finite bounded ratings across representative rating gaps', () => {
    const ratings = [100, 500, 1000, 1500, 2000, 2500, 3000];
    const results: Array<0 | 0.5 | 1> = [0, 0.5, 1];
    const games = [0, 19, 20, 99, 100, 500];

    for (const ratingA of ratings) {
      for (const ratingB of ratings) {
        for (const result of results) {
          for (const played of games) {
            const delta = eloDelta(ratingA, ratingB, result, played);
            const after = applyRating(ratingA, delta);
            expect(Number.isFinite(delta)).toBe(true);
            expect(after).toBeGreaterThanOrEqual(100);
            expect(after).toBeLessThanOrEqual(3000);
          }
        }
      }
    }
  });
});
