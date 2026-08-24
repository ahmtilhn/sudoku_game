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
const schemaSource = readFileSync(
  new URL('../src/rank_progression_schema.ts', import.meta.url),
  'utf8',
);
const resultSource = readFileSync(
  new URL('../src/rank_match_result.ts', import.meta.url),
  'utf8',
);
const clientSource = readFileSync(
  new URL('../../../lib/services/rank_identity_service.dart', import.meta.url),
  'utf8',
);
const migration = readFileSync(
  new URL('../migrations/0024_rank_progression_identity.sql', import.meta.url),
  'utf8',
);
const recoveryMigration = readFileSync(
  new URL('../migrations/0026_rank_progression_start_backfill.sql', import.meta.url),
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

  it('retries reconciliation before exposing an unsettled ranked result', () => {
    expect(resultSource).toContain('RANK_RESULT_RECONCILE_ATTEMPTS = 4');
    expect(resultSource).toContain('await reconcileRankProgression');
    expect(resultSource).toContain('await rankSettlementForMatch');
    expect(resultSource).toContain('retryAfterMs: 300');
    expect(resultSource.indexOf('await reconcileRankProgression')).toBeLessThan(
      resultSource.indexOf('await refreshRankPostSettlement'),
    );
  });

  it('keeps the Flutter result client alive across the normal RP propagation window', () => {
    expect(clientSource).toContain('const maxAttempts = 16');
    expect(clientSource).toContain('error.statusCode == 429');
    expect(clientSource).toContain('error.statusCode >= 500');
    expect(clientSource).toContain('boundedAttempt');
  });

  it('repairs only untouched progression rows whose start baseline skipped rated matches', () => {
    for (const text of [schemaSource, recoveryMigration]) {
      expect(text).toContain('2026-08-19T13:45:00.000Z');
      expect(text).toContain('ranked_games = 0');
      expect(text).toContain('NOT EXISTS');
      expect(text).toContain('rank_progression_settlements');
    }
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
