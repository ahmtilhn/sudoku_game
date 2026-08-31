import { describe, expect, it } from 'vitest';

import {
  handleAchievementClaimRequest,
  isAchievementClaimRoute,
} from '../src/achievement_claim_wrapper';

describe('achievement claim compatibility wrapper', () => {
  it('recognizes only achievement claim paths', () => {
    expect(isAchievementClaimRoute('/v1/achievements/wins_10/claim')).toBe(true);
    expect(isAchievementClaimRoute('/v1/achievements')).toBe(false);
    expect(isAchievementClaimRoute('/v1/me/wallet')).toBe(false);
  });

  it('returns the wallet for an already server-unlocked achievement', async () => {
    const calls: string[] = [];
    const response = await handleAchievementClaimRequest(
      new Request('https://example.test/v1/achievements/wins_10/claim', {
        method: 'POST',
        headers: { authorization: 'Bearer test' },
      }),
      async (request) => {
        const path = new URL(request.url).pathname;
        calls.push(path);
        if (path === '/v1/achievements') {
          return Response.json({
            achievements: [
              { id: 'wins_10', unlocked: true },
              { id: 'games_25', unlocked: false },
            ],
          });
        }
        if (path === '/v1/me/wallet') {
          return Response.json({ balance: 1234, canEnterOnline: true });
        }
        return new Response('unexpected', { status: 500 });
      },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ balance: 1234 });
    expect(calls).toEqual(['/v1/achievements', '/v1/me/wallet']);
  });

  it('rejects a known achievement that the authoritative state has not unlocked', async () => {
    const response = await handleAchievementClaimRequest(
      new Request('https://example.test/v1/achievements/games_25/claim', {
        method: 'POST',
      }),
      async (request) => {
        const path = new URL(request.url).pathname;
        if (path === '/v1/achievements') {
          return Response.json({
            achievements: [{ id: 'games_25', unlocked: false }],
          });
        }
        return new Response('unexpected', { status: 500 });
      },
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({
      code: 'achievement_incomplete',
    });
  });

  it('rejects unknown reward IDs without falling through to legacy classic9 verification', async () => {
    const response = await handleAchievementClaimRequest(
      new Request('https://example.test/v1/achievements/not_real/claim', {
        method: 'POST',
      }),
      async (request) => {
        const path = new URL(request.url).pathname;
        if (path === '/v1/achievements') {
          return Response.json({ achievements: [] });
        }
        return new Response('unexpected', { status: 500 });
      },
    );

    expect(response.status).toBe(404);
    expect(await response.json()).toMatchObject({ code: 'achievement_unknown' });
  });
});
