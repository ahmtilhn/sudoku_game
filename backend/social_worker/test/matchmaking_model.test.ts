import { describe, expect, it } from 'vitest';

import { joinQueueForTest, pairKey } from '../src/matchmaking_model';

describe('matchmaking race and abuse model', () => {
  it('deduplicates the same player queue join', () => {
    const tickets = [];
    joinQueueForTest({ tickets, playerId: 'a', difficulty: 'easy', rating: 1000, now: 1 });
    joinQueueForTest({ tickets, playerId: 'a', difficulty: 'easy', rating: 1100, now: 2 });

    expect(tickets).toHaveLength(1);
    expect(tickets[0].rating).toBe(1100);
  });

  it('does not match a player with self and rejects active match players', () => {
    const tickets = [{ playerId: 'a', difficulty: 'easy', rating: 1000, joinedAt: 1 }];

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
      { playerId: 'low', difficulty: 'medium', rating: 700, joinedAt: 1 },
      { playerId: 'blocked', difficulty: 'medium', rating: 1010, joinedAt: 2 },
      { playerId: 'near', difficulty: 'medium', rating: 1040, joinedAt: 3 },
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
});
