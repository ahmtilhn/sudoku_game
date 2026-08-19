import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';
import {
  RANK_TIERS,
  RankProgressionError,
  reconcileRankProgression,
  tierForPoints,
  type RankProgressionEnv,
} from './rank_progression';

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

export function isRankMatchResultRoute(pathname: string): boolean {
  return /^\/v1\/me\/rank-match-result\/[^/]+$/.test(pathname);
}

/**
 * Returns only player-facing RP settlement data. Hidden Elo/MMR values are
 * intentionally not returned even though they are retained in the audit row.
 *
 * This endpoint reconciles from the already-authoritative match settlement. It
 * never participates in GameRoom, WebSocket, matchmaking, move or Elo logic.
 */
export async function handleRankMatchResultRequest(
  request: Request,
  env: RankProgressionEnv,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    if (request.method !== 'GET') {
      return json(env, 405, {
        error: 'Method not allowed.',
        code: 'method_not_allowed',
      });
    }

    const uid = await authenticateFirebase(request, env);
    const player = await env.DB.prepare(
      'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
    )
      .bind(uid)
      .first<{ id: string }>();
    if (!player) {
      throw new RankProgressionError(
        404,
        'Player profile not found.',
        'player_not_found',
      );
    }

    const url = new URL(request.url);
    const matchId = decodeURIComponent(url.pathname.split('/').at(-1) ?? '');
    if (!matchId || matchId.length > 100) {
      throw new RankProgressionError(
        400,
        'Invalid match id.',
        'invalid_match_id',
      );
    }

    await reconcileRankProgression(env, player.id);

    const settlement = await env.DB.prepare(
      `SELECT match_id, result, finish_reason, base_delta, alignment_percent,
              repeat_percent, abandonment_penalty, rp_delta, rp_before, rp_after,
              rank_before, rank_after, finished_at
       FROM rank_progression_settlements
       WHERE match_id = ? AND player_id = ?
       LIMIT 1`,
    )
      .bind(matchId, player.id)
      .first<Record<string, unknown>>();

    if (!settlement) {
      const match = await env.DB.prepare(
        `SELECT mode, rated, status, finished_at
         FROM matches
         WHERE id = ? AND (player_a_id = ? OR player_b_id = ?)
         LIMIT 1`,
      )
        .bind(matchId, player.id, player.id)
        .first<Record<string, unknown>>();
      if (!match) {
        throw new RankProgressionError(404, 'Match not found.', 'match_not_found');
      }
      if (String(match.mode ?? '') !== 'ranked' || Number(match.rated ?? 0) !== 1) {
        return json(env, 200, {
          matchId,
          rated: false,
          settled: true,
        });
      }
      return json(env, 202, {
        matchId,
        rated: true,
        settled: false,
        status: String(match.status ?? ''),
      });
    }

    const before = Number(settlement.rp_before ?? 0);
    const after = Number(settlement.rp_after ?? 0);
    const beforeTier = tierForPoints(before);
    const afterTier = tierForPoints(after);
    const crossed = after > before
      ? RANK_TIERS.filter(
          (tier) => tier.minPoints > before && tier.minPoints <= after,
        )
      : [];

    if (crossed.length > 0) {
      const now = new Date().toISOString();
      await env.DB.batch(
        crossed
          .filter((tier) => tier.rewardCoins > 0)
          .map((tier) =>
            env.DB.prepare(
              `INSERT OR IGNORE INTO rank_reward_grants (
                 player_id, rank_key, amount, granted_at
               ) VALUES (?, ?, ?, ?)`,
            ).bind(player.id, tier.key, tier.rewardCoins, now),
          ),
      );
    }

    return json(env, 200, {
      matchId,
      rated: true,
      settled: true,
      result: settlement.result,
      finishReason: settlement.finish_reason ?? null,
      rpBefore: before,
      rpAfter: after,
      rpDelta: Number(settlement.rp_delta ?? 0),
      rankBeforeKey: String(settlement.rank_before ?? beforeTier.key),
      rankBeforeName: beforeTier.label,
      rankAfterKey: String(settlement.rank_after ?? afterTier.key),
      rankAfterName: afterTier.label,
      rankUp: afterTier.minPoints > beforeTier.minPoints,
      rewardCoins: crossed.reduce((sum, tier) => sum + tier.rewardCoins, 0),
      rewards: crossed
        .filter((tier) => tier.rewardCoins > 0)
        .map((tier) => ({
          rankKey: tier.key,
          rankName: tier.label,
          amount: tier.rewardCoins,
        })),
      abandonmentPenalty: Number(settlement.abandonment_penalty ?? 0),
      repeatPercent: Number(settlement.repeat_percent ?? 100),
      baseDelta: Number(settlement.base_delta ?? 0),
      alignmentPercent: Number(settlement.alignment_percent ?? 100),
      finishedAt: settlement.finished_at,
    });
  } catch (error) {
    if (error instanceof AppCheckError) {
      return json(env, 403, { error: error.message, code: error.code });
    }
    if (error instanceof RankProgressionError) {
      return json(env, error.status, { error: error.message, code: error.code });
    }
    console.error('rank_match_result_failed', error);
    return json(env, 500, {
      error: 'Rank result is temporarily unavailable.',
      code: 'rank_match_result_failed',
    });
  }
}

async function authenticateFirebase(
  request: Request,
  env: RankProgressionEnv,
): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) {
    throw new RankProgressionError(401, 'Missing bearer token.', 'missing_auth');
  }
  const token = header.slice(7).trim();
  if (!token) {
    throw new RankProgressionError(401, 'Missing bearer token.', 'missing_auth');
  }
  try {
    const verified = await jwtVerify(token, FIREBASE_JWKS, {
      algorithms: ['RS256'],
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
      audience: env.FIREBASE_PROJECT_ID,
    });
    if (!verified.payload.sub) throw new Error('Missing subject.');
    return verified.payload.sub;
  } catch {
    throw new RankProgressionError(
      401,
      'Invalid or expired Firebase ID token.',
      'invalid_auth',
    );
  }
}

function json(
  env: RankProgressionEnv,
  status: number,
  body: unknown,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': env.ALLOWED_ORIGIN || '*',
      'access-control-allow-headers':
        'authorization, content-type, x-firebase-appcheck',
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
    },
  });
}
