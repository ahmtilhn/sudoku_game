import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const source = readFileSync(
  new URL('../src/rank_progression.ts', import.meta.url),
  'utf8',
);

describe('visible RP reconciliation scope', () => {
  it('requires both rated and ranked authoritative matches', () => {
    expect(source).toContain('AND m.rated = 1');
    expect(source).toContain("AND m.mode = 'ranked'");
  });

  it('keeps visible RP out of the authoritative duel engine', () => {
    for (const forbidden of [
      'GameRoom',
      'MatchmakingQueue',
      'UPDATE matches',
      'UPDATE match_players',
      'UPDATE player_ratings',
      'UPDATE player_variant_ratings',
      'match_coin_escrow',
      'match_coin_settlements',
    ]) {
      expect(source).not.toContain(forbidden);
    }
  });
});
