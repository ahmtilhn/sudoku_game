import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import { ENTRY_FEES, potForDifficulty } from '../src/economy';

describe('dynamic duel escrow payout contract', () => {
  it('keeps every winner pot equal to both entry fees', () => {
    for (const [difficulty, entryFee] of Object.entries(ENTRY_FEES)) {
      expect(potForDifficulty(difficulty)).toBe(entryFee * 2);
    }
  });

  it('pays the persisted escrow pot to the winner and refunds draws dynamically', () => {
    const migration = readFileSync(
      new URL('../migrations/0019_dynamic_duel_fees_no_ads_entitlement.sql', import.meta.url),
      'utf8',
    );
    expect(migration).toContain(
      'SELECT pot_amount FROM match_coin_escrow WHERE match_id = NEW.match_id',
    );
    expect(migration).toContain("'match_payout'");
    expect(migration).toContain(
      'SELECT player_a_amount FROM match_coin_escrow WHERE match_id = NEW.id',
    );
    expect(migration).toContain(
      'SELECT player_b_amount FROM match_coin_escrow WHERE match_id = NEW.id',
    );
  });
});
