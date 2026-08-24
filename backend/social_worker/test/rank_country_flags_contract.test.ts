import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const source = readFileSync(
  new URL('../src/rank_country_flags.ts', import.meta.url),
  'utf8',
);
const entry = readFileSync(
  new URL('../src/entry_v2.ts', import.meta.url),
  'utf8',
);
const migration = readFileSync(
  new URL('../migrations/0025_rank_country_flag_visibility.sql', import.meta.url),
  'utf8',
);

describe('ranked country flags', () => {
  it('uses an explicit player preference instead of inferred location', () => {
    expect(source).toContain("'/v1/me/rank-country'");
    expect(source).toContain('validateCountryCode');
    expect(source).toContain('ISO_COUNTRY_CODES');
    expect(source).not.toContain('request.cf');
    expect(source).not.toContain('cf.country');
    expect(source).not.toContain('geoip');
    expect(source).not.toContain('ipAddress');
  });

  it('never exposes a hidden country in the public ladder response', () => {
    expect(source).toContain('countryFlagVisible');
    expect(source).toContain('country_flag_visible');
    expect(source).toContain(
      'countryCode: visible ? normalizeCountryCode(row.country_code) : null',
    );
  });

  it('keeps flag ordering aligned with the visible RP ladder', () => {
    expect(source).toContain('FROM player_rank_progression rp');
    expect(source).toContain('WHERE rp.ranked_games > 0');
    expect(source).toContain('AND (COALESCE(p.discoverable, 1) = 1 OR p.id = ?)');
    expect(source).toContain(
      'ORDER BY rp.rank_points DESC, rp.ranked_games DESC, rp.updated_at ASC, rp.player_id ASC',
    );
  });

  it('uses an idempotent additive visibility table', () => {
    expect(migration).toContain(
      'CREATE TABLE IF NOT EXISTS player_country_preferences',
    );
    expect(migration).toContain('country_flag_visible INTEGER NOT NULL DEFAULT 1');
    expect(source).toContain(
      'CREATE TABLE IF NOT EXISTS player_country_preferences',
    );
  });

  it('is wired through the additive rank wrapper without touching matchmaking', () => {
    expect(entry).toContain('isRankCountryFlagRoute(url.pathname)');
    expect(entry).toContain('handleRankCountryFlagRequest(');
    expect(source).not.toContain('MatchmakingQueue');
    expect(source).not.toContain('GameRoom');
    expect(source).not.toContain('player_ratings');
    expect(source).not.toContain('match_coin_escrow');
  });
});
