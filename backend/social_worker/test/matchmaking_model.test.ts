import { describe, expect, it } from 'vitest';

import {
  joinQueueForTest,
  matchmakingRatingDeltaForWaitMs,
  pairKey,
} from '../src/matchmaking_model';

describe('matchmaking race and abuse model', () => {
  it('deduplicates the same player queue join', () => {
    const tickets = [];
    joinQueueForTest({
      tickets,
      playerId: 'a',
      difficulty: 'easy',
      rating: 1000,
      now: 1,
    });
    joinQueueForTest({
      tickets,
      playerId: 'a',
      difficulty: 'easy',
      rating: 1100,
      now: 2,
    });

    expect(tickets).toHaveLength(1);
    expect(tickets[0].rating).toBe(1100);
  });

  it('does not match a player with self and rejects active match players', () => {
    const tickets = [
      {
        playerId: 'a',
        difficulty: 'easy',
        rating: 1000,
        joinedAt: 1,
      },
    ];

    expect(() =>
      joinQueueForTest({
        tickets,
        playerId: 'b',
        difficulty: 'easy',
        rating: 1000,
        now: 2,
        activePlayers: new Set(['b']),
      }),
    ).toThrow('active_match_exists');
    expect(tickets.find((ticket) => ticket.playerId === 'a')).toBeTruthy();
  });

  it('skips blocked players and chooses nearest rating', () => {
    const tickets = [
      {
        playerId: 'low',
        difficulty: 'medium',
        rating: 700,
        joinedAt: 1,
      },
      {
        playerId: 'blocked',
        difficulty: 'medium',
        rating: 1010,
        joinedAt: 2,
      },
      {
        playerId: 'near',
        difficulty: 'medium',
        rating: 1040,
        joinedAt: 3,
      },
    ];
    const decision = joinQueueForTest({
      tickets,
      playerId: 'me',
      difficulty: 'medium',
      rating: 1000,
      now: 4,
      blockedPairs: new Set([pairKey('blocked', 'me')]),
    });

    expect(decision.status).toBe('matched');
    if (decision.status === 'matched') {
      expect(decision.playerA.playerId).toBe('near');
      expect(decision.roomId).toBe(pairKey('near', 'me'));
    }
  });

  it('uses the agreed progressive hidden-MMR windows', () => {
    expect(matchmakingRatingDeltaForWaitMs(0)).toBe(150);
    expect(matchmakingRatingDeltaForWaitMs(4_999)).toBe(150);
    expect(matchmakingRatingDeltaForWaitMs(5_000)).toBe(300);
    expect(matchmakingRatingDeltaForWaitMs(10_000)).toBe(500);
    expect(matchmakingRatingDeltaForWaitMs(15_000)).toBe(750);
    expect(matchmakingRatingDeltaForWaitMs(20_000)).toBe(10_000);
  });

  it('keeps 9x9 and 16x16 in hard-separated queues even after 20 seconds', () => {
    const tickets = [
      {
        playerId: 'sixteen',
        difficulty: 'medium',
        rating: 1000,
        joinedAt: 0,
        variant: 'classic16',
      },
    ];

    const decision = joinQueueForTest({
      tickets,
      playerId: 'nine',
      difficulty: 'easy',
      rating: 1000,
      now: 25_000,
      variant: 'classic9',
    });

    expect(decision.status).toBe('queued');
    expect(tickets).toHaveLength(2);
  });

  it('widens rating only after both players have waited long enough', () => {
    const tickets = [
      {
        playerId: 'candidate',
        difficulty: 'easy',
        rating: 1300,
        joinedAt: 0,
        variant: 'classic9',
      },
      {
        playerId: 'me',
        difficulty: 'easy',
        rating: 1000,
        joinedAt: 0,
        variant: 'classic9',
      },
    ];

    const tooEarly = joinQueueForTest({
      tickets,
      playerId: 'me',
      difficulty: 'easy',
      rating: 1000,
      now: 4_999,
      variant: 'classic9',
    });
    expect(tooEarly.status).toBe('queued');

    const widened = joinQueueForTest({
      tickets,
      playerId: 'me',
      difficulty: 'easy',
      rating: 1000,
      now: 5_000,
      variant: 'classic9',
    });
    expect(widened.status).toBe('matched');
  });

  it('prioritizes same difficulty but allows another difficulty in the same variant', () => {
    const tickets = [
      {
        playerId: 'cross-difficulty',
        difficulty: 'easy',
        rating: 1005,
        joinedAt: 0,
        variant: 'classic16',
      },
      {
        playerId: 'same-difficulty',
        difficulty: 'medium',
        rating: 1100,
        joinedAt: 0,
        variant: 'classic16',
      },
    ];

    const decision = joinQueueForTest({
      tickets,
      playerId: 'me',
      difficulty: 'medium',
      rating: 1000,
      now: 1_000,
      variant: 'classic16',
    });

    expect(decision.status).toBe('matched');
    if (decision.status === 'matched') {
      expect(decision.playerA.playerId).toBe('same-difficulty');
    }
  });
});
