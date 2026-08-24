import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const matchmaking = readFileSync(
  new URL('../src/variant_matchmaking.ts', import.meta.url),
  'utf8',
);
const progression = readFileSync(
  new URL('../src/rank_progression.ts', import.meta.url),
  'utf8',
);
const duelView = readFileSync(
  new URL('../src/online_duel_view.ts', import.meta.url),
  'utf8',
);
const initialMigration = readFileSync(
  new URL('../migrations/0001_init.sql', import.meta.url),
  'utf8',
);

describe('hidden MMR and visible RP alignment contract', () => {
  it('starts hidden Elo/MMR at 1000 and never treats visible zero RP as zero MMR', () => {
    expect(initialMigration).toContain('rating INTEGER NOT NULL DEFAULT 1000');
    expect(duelView).toContain('Math.max(100, Math.min(3000');
  });

  it('uses global hidden MMR as the ranked matchmaking skill signal', () => {
    expect(matchmaking).toContain("VALUES (?, ?, 'global', ?)");
    expect(matchmaking).toContain("scope = 'global'");
    expect(matchmaking).toContain('global hidden MMR snapshot');
  });

  it('derives visible RP from the same pre-match global MMR snapshot', () => {
    expect(progression).toContain('mp.rating_before_global');
    expect(progression).toContain('opponent.rating_before_global');
    expect(progression).toContain('baseRankDelta(playerMmr, opponentMmr');
  });

  it('keeps the agreed Elo K factors and expected-score formula', () => {
    expect(duelView).toContain('10 ** ((b - a) / 400)');
    expect(duelView).toContain('gamesPlayed < 20 ? 40');
    expect(duelView).toContain('gamesPlayed < 100 ? 24 : 16');
  });
});
