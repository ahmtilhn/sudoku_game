import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const indexSource = readFileSync(
  new URL('../src/index.ts', import.meta.url),
  'utf8',
);
const runtimeSource = readFileSync(
  new URL('../src/runtime_schema.ts', import.meta.url),
  'utf8',
);
const mainSource = readFileSync(
  new URL('../src/main.ts', import.meta.url),
  'utf8',
);

describe('challenge lifecycle hardening', () => {
  it('exposes exact status and challenger cancellation routes', () => {
    expect(indexSource).toContain('async function getChallenge');
    expect(indexSource).toContain('async function cancelChallenge');
    expect(indexSource).toContain("request.method === 'DELETE'");
  });

  it('requires funded escrow before returning an accepted room', () => {
    expect(indexSource).toContain("funded?.status !== 'funded'");
    expect(indexSource).toContain('Both players need enough Coin');
  });

  it('prevents duplicate pending challenges and terminal room replay', () => {
    expect(runtimeSource).toContain('challenges_unique_pending_direction_idx');
    const activeStatuses =
      "status IN ('waiting', 'ready_window', 'countdown', 'active', 'paused')";
    expect(indexSource).toContain(activeStatuses);
    expect(mainSource).toContain(activeStatuses);
  });

  it('records recent opponents during authoritative settlement', () => {
    expect(indexSource).toContain('INSERT INTO recent_opponents');
    expect(indexSource).toContain(
      'last_winner_id = excluded.last_winner_id',
    );
    expect(indexSource).toContain('duel.startedAt !== null');
  });
});
