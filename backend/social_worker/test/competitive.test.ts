import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import {
  compareLeaderboardRows,
  decodeLeaderboardCursor,
  encodeLeaderboardCursor,
  nextDailyState,
  platformMirrorRetryState,
  rankName,
  winRate,
} from '../src/competitive';

describe('competitive profile model', () => {
  it('uses deterministic multi-field leaderboard ordering', () => {
    const rows = [
      {
        playerId: 'b',
        rating: 1200,
        gamesPlayed: 12,
        wins: 8,
        draws: 1,
        updatedAt: '2026-01-01T00:00:02.000Z',
      },
      {
        playerId: 'a',
        rating: 1200,
        gamesPlayed: 12,
        wins: 8,
        draws: 1,
        updatedAt: '2026-01-01T00:00:02.000Z',
      },
      {
        playerId: 'c',
        rating: 1200,
        gamesPlayed: 12,
        wins: 9,
        draws: 0,
        updatedAt: '2026-01-01T00:00:03.000Z',
      },
    ].sort(compareLeaderboardRows);

    expect(rows.map((row) => row.playerId)).toEqual(['c', 'a', 'b']);
  });

  it('round trips pagination cursors without trusting client rank', () => {
    const cursor = {
      rating: 1300,
      gamesPlayed: 20,
      wins: 12,
      draws: 2,
      updatedAt: '2026-01-01T00:00:00.000Z',
      playerId: 'player-1',
    };

    expect(decodeLeaderboardCursor(encodeLeaderboardCursor(cursor))).toEqual(
      cursor,
    );
    expect(decodeLeaderboardCursor('not-json')).toBeNull();
  });

  it('calculates daily reward streaks from UTC day only', () => {
    const first = nextDailyState(null, 0, new Date('2026-07-28T23:30:00Z'));
    const duplicate = nextDailyState(
      first.utcDay,
      first.streak,
      new Date('2026-07-28T23:59:00Z'),
    );
    const next = nextDailyState(
      first.utcDay,
      first.streak,
      new Date('2026-07-29T00:01:00Z'),
    );

    expect(first).toMatchObject({ utcDay: '2026-07-28', streak: 1 });
    expect(duplicate.duplicate).toBe(true);
    expect(next).toMatchObject({ utcDay: '2026-07-29', streak: 2 });
  });

  it('keeps profile math stable for empty and deleted-user-like stats', () => {
    expect(winRate(0, 0, 0)).toBe(0);
    expect(rankName(1000)).toBe('Bronze');
    expect(rankName(1500)).toBe('Platinum');
  });

  it('does not roll back backend unlock on platform mirror failure', () => {
    expect(platformMirrorRetryState(false, 2)).toEqual({
      queueStatus: 'failed',
      unlockPreserved: true,
      attempts: 3,
    });
  });

  it('keeps future leaderboard scopes out of active routing', () => {
    const source = readFileSync('src/profile_wrapper.ts', 'utf8');

    expect(source).toContain(
      "scopes: ['global', 'beginner', 'easy', 'medium', 'hard', 'expert']",
    );
    expect(source).toContain("'futureScopes'");
    expect(source).not.toContain("scope === 'country'");
    expect(source).not.toContain("scope === 'current_season'");
    expect(source).not.toContain("scope === 'daily_tournament'");
    expect(source).not.toContain("scope === 'weekend_tournament'");
    expect(source).not.toContain("scope === 'countries'");
  });

  it('returns rank and placement stats from leaderboard rows', () => {
    const source = readFileSync('src/competitive.ts', 'utf8');

    expect(source).toContain('ROW_NUMBER() OVER');
    expect(source).toContain('winStreak: Number(row.win_streak ?? 0)');
    expect(source).toContain('bestRating: Number(row.best_rating ?? row.rating ?? 1000)');
    expect(source).toContain('provisionalGames: Number(row.provisional_games ?? 0)');
    expect(source).toContain('currentRankOverride');
  });
});
