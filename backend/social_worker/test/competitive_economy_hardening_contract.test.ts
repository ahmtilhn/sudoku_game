import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const matchmaking = readFileSync(
  new URL('../src/variant_matchmaking.ts', import.meta.url),
  'utf8',
);
const hardening = readFileSync(
  new URL('../src/competitive_economy_hardening.ts', import.meta.url),
  'utf8',
);
const migration = readFileSync(
  new URL(
    '../migrations/0027_competitive_economy_hardening.sql',
    import.meta.url,
  ),
  'utf8',
);
const entry = readFileSync(
  new URL('../src/entry_v2.ts', import.meta.url),
  'utf8',
);

describe('competitive economy hardening', () => {
  it('keeps legacy rematch funding compatible with the production matchmaking DO', () => {
    expect(matchmaking).toContain("if (url.pathname === '/fund')");
    expect(matchmaking).toContain('await createFundedMatch(this.env, input)');
    expect(matchmaking).toContain("mode !== 'friendly' && mode !== 'ranked'");
  });

  it('treats an active match as account-wide instead of variant-local', () => {
    const activeQueryStart = matchmaking.indexOf(
      'SELECT room_id, difficulty, variant, board_size, cell_count',
    );
    const activeQueryEnd = matchmaking.indexOf(
      'ORDER BY created_at DESC',
      activeQueryStart,
    );
    const activeQuery = matchmaking.slice(activeQueryStart, activeQueryEnd);
    expect(activeQuery).toContain('(player_a_id = ? OR player_b_id = ?)');
    expect(activeQuery).not.toContain('AND variant = ?');
  });

  it('keeps pairing alive when the rolling ranked pair allowance is exhausted', () => {
    expect(matchmaking).toContain('MAX_RATED_PAIR_MATCHES_24H');
    expect(matchmaking).toContain('rankedPairCutoff');
    expect(matchmaking).toContain('recentRatedPairMatchCount');
    expect(matchmaking).toContain(
      "recentPairMatches >= MAX_RATED_PAIR_MATCHES_24H ? 'friendly' : 'ranked'",
    );
    expect(matchmaking).toContain("recent.mode = 'ranked'");
  });

  it('enforces one active room and the pair cap at the database boundary', () => {
    for (const source of [hardening, migration]) {
      expect(source).toContain('enforce_single_active_match_before_insert');
      expect(source).toContain('enforce_single_active_match_before_reactivate');
      expect(source).toContain("RAISE(ABORT, 'active_match_conflict')");
      expect(source).toContain('enforce_ranked_pair_limit_before_insert');
      expect(source).toContain("RAISE(ABORT, 'ranked_pair_limit')");
    }
  });

  it('requires negative legacy debits to prove that the wallet actually moved', () => {
    for (const source of [hardening, migration]) {
      expect(source).toContain(
        "NEW.reason IN ('match_entry', 'career_continue')",
      );
      expect(source).toContain('ORDER BY created_at DESC, rowid DESC');
      expect(source).toContain("RAISE(ABORT, 'coin_debit_balance_invariant')");
    }
  });

  it('makes payout and refund wallet mutations idempotent before crediting', () => {
    for (const source of [hardening, migration]) {
      expect(source).toContain(
        "idempotency_key = 'match_payout:' || NEW.match_id",
      );
      expect(source).toContain(
        "idempotency_key = 'match_refund:' || NEW.id || ':' || NEW.player_a_id",
      );
      expect(source).toContain(
        "idempotency_key = 'match_refund:' || NEW.id || ':' || NEW.player_b_id",
      );
      expect(source).toContain('validate_match_coin_settlement_before_insert');
      expect(source).toContain("RAISE(ABORT, 'invalid_match_coin_settlement')");
    }
  });

  it('installs the hardening before entry_v2 routes requests', () => {
    expect(entry).toContain("from './competitive_economy_hardening'");
    expect(entry).toContain('await ensureCompetitiveEconomyHardening(env)');
    const install = entry.indexOf(
      'await ensureCompetitiveEconomyHardening(env)',
    );
    const rankRoute = entry.indexOf('isRankProgressionRoute(url.pathname)');
    expect(install).toBeGreaterThanOrEqual(0);
    expect(rankRoute).toBeGreaterThan(install);
  });
});
