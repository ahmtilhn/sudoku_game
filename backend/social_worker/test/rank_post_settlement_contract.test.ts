import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const source = readFileSync(
  new URL('../src/rank_post_settlement.ts', import.meta.url),
  'utf8',
);
const progressionSource = readFileSync(
  new URL('../src/rank_progression.ts', import.meta.url),
  'utf8',
);
const resultSource = readFileSync(
  new URL('../src/rank_match_result.ts', import.meta.url),
  'utf8',
);
const migration = readFileSync(
  new URL('../migrations/0024_rank_progression_identity.sql', import.meta.url),
  'utf8',
);

describe('rank post-settlement safety boundary', () => {
  it('derives rewards, cosmetics and achievements only from RP state', () => {
    expect(source).toContain('player_rank_progression');
    expect(source).toContain('rank_progression_settlements');
    expect(source).toContain('rank_reward_grants');
    expect(source).toContain('player_achievements');
    expect(source).toContain('achievement_showcase');
    expect(source).toContain('players');
  });

  it('does not mutate online match authority, escrow, rooms or Elo rows', () => {
    const forbidden = [
      'match_coin_escrow',
      'match_coin_settlements',
      'player_ratings',
      'player_variant_ratings',
      'GameRoom',
      'WebSocket',
      'MatchmakingQueue',
      'UPDATE matches',
      'UPDATE match_players',
    ];
    for (const token of forbidden) {
      expect(source).not.toContain(token);
      expect(progressionSource).not.toContain(token);
    }
  });

  it('is invoked only after the normal RP reconciliation in the result route', () => {
    const reconcile = resultSource.indexOf('await reconcileRankProgression');
    const derived = resultSource.indexOf('await refreshRankPostSettlement');
    expect(reconcile).toBeGreaterThanOrEqual(0);
    expect(derived).toBeGreaterThan(reconcile);
  });

  it('keeps lifetime Coin grants idempotent at the database boundary', () => {
    expect(migration).toContain('PRIMARY KEY(player_id, rank_key)');
    expect(migration).toContain(
      'CREATE TRIGGER IF NOT EXISTS rank_reward_grant_apply',
    );
    expect(migration).toContain('online_coins = online_coins + NEW.amount');
    expect(migration).toContain("'rank_reward:' || NEW.player_id || ':' || NEW.rank_key");
  });

  it('applies the agreed abandonment penalty only to ranked loss reasons', () => {
    expect(progressionSource).toContain("'explicit_forfeit'");
    expect(progressionSource).toContain("'disconnect_forfeit'");
    expect(progressionSource).toContain("'consecutive_timeouts'");
    expect(progressionSource).toContain('const ABANDONMENT_PENALTY = 8');
    expect(progressionSource).toContain("match.result === 'loss'");
  });

  it('does not multiply RP by score margin, speed or a win streak', () => {
    expect(progressionSource).not.toContain('scoreMargin');
    expect(progressionSource).not.toContain('speedBonus');
    expect(progressionSource).not.toContain('winStreakMultiplier');
    expect(progressionSource).toContain('const base = baseRankDelta(');
  });
});
