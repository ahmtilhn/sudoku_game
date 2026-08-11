import { describe, expect, it } from 'vitest';

import {
  type SettlementFailpoint,
  createSettlementStore,
  settleForTest,
} from '../src/settlement_model';

const failpoints: SettlementFailpoint[] = [
  'after_match_completed',
  'after_match_players',
  'after_global_rating',
  'after_difficulty_rating',
  'after_player_aggregate',
  'after_recent_opponents',
  'after_challenge_completed',
  'before_marker',
  'after_marker',
];

describe('settlement retry model', () => {
  for (const failpoint of failpoints) {
    it(`retries idempotently after ${failpoint}`, () => {
      const store = createSettlementStore();
      expect(() => settleForTest(store, failpoint)).toThrow();
      settleForTest(store);
      settleForTest(store);

      expect(store.marker).toBe(true);
      expect(store.winner).toBe('a');
      expect(store.globalRatings).toEqual({ a: 1020, b: 980 });
      expect(store.difficultyRatings).toEqual({ a: 1020, b: 980 });
      expect(store.gamesPlayed).toEqual({ a: 1, b: 1 });
      expect(store.wins).toEqual({ a: 1, b: 0 });
      expect(store.losses).toEqual({ a: 0, b: 1 });
      expect(store.historyRows.size).toBe(2);
      expect(store.auditSequences.size).toBe(1);
      expect(store.recentOpponents.size).toBe(1);
      expect(store.challengeCompleted).toBe(true);
    });
  }

  it('handles two sequential settlement calls as one result', () => {
    const store = createSettlementStore();
    settleForTest(store);
    settleForTest(store);

    expect(store.gamesPlayed.a).toBe(1);
    expect(store.historyRows.size).toBe(2);
    expect(store.auditSequences.size).toBe(1);
  });
});
