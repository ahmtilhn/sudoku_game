import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';
import {
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

export function isPublicRankProfileRoute(pathname: string): boolean {
  return /^\/v1\/competitive\/rank-player\/[^/]+$/.test(pathname);
}

/**
 * Public, privacy-aware visible-rank summary for matchup cards.
 * Hidden Elo/MMR is never returned by this route.
 */
export async function handlePublicRankProfileRequest(
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
    const viewer = await env.DB.prepare(
      'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
    )
      .bind(uid)
      .first<{ id: string }>();
    if (!viewer) {
      throw new RankProgressionError(
        404,
        'Player profile not found.',
        'player_not_found',
      );
    }

    const url = new URL(request.url);
    const publicId = decodeURIComponent(url.pathname.split('/').at(-1) ?? '')
      .trim()
      .toUpperCase();
    if (!publicId || publicId.length > 64) {
      throw new RankProgressionError(
        400,
        'Invalid player id.',
        'invalid_public_id',
      );
    }

    const target = await env.DB.prepare(
      `SELECT id, public_id, username, display_name, avatar_key,
              COALESCE(discoverable, 1) AS discoverable
       FROM players
       WHERE public_id = ?
       LIMIT 1`,
    )
      .bind(publicId)
      .first<{
        id: string;
        public_id: string;
        username: string;
        display_name: string;
        avatar_key: string;
        discoverable: number;
      }>();
    if (!target || (target.id !== viewer.id && target.discoverable !== 1)) {
      throw new RankProgressionError(
        404,
        'Player rank profile is not available.',
        'rank_profile_private',
      );
    }

    await reconcileRankProgression(env, target.id);
    const progression = await env.DB.prepare(
      `SELECT rank_points, ranked_games, ranked_wins, ranked_losses, ranked_draws
       FROM player_rank_progression
       WHERE player_id = ?
       LIMIT 1`,
    )
      .bind(target.id)
      .first<{
        rank_points: number;
        ranked_games: number;
        ranked_wins: number;
        ranked_losses: number;
        ranked_draws: number;
      }>();

    const points = Number(progression?.rank_points ?? 0);
    const games = Number(progression?.ranked_games ?? 0);
    const wins = Number(progression?.ranked_wins ?? 0);
    const tier = tierForPoints(points);

    return json(env, 200, {
      publicId: target.public_id,
      username: target.username,
      displayName: target.display_name,
      avatarKey: target.avatar_key,
      rankPoints: points,
      rankKey: tier.key,
      rankName: tier.label,
      gamesPlayed: games,
      wins,
      losses: Number(progression?.ranked_losses ?? 0),
      draws: Number(progression?.ranked_draws ?? 0),
      winRate: games === 0 ? 0 : wins / games,
    });
  } catch (error) {
    if (error instanceof AppCheckError) {
      return json(env, 403, { error: error.message, code: error.code });
    }
    if (error instanceof RankProgressionError) {
      return json(env, error.status, { error: error.message, code: error.code });
    }
    console.error('public_rank_profile_failed', error);
    return json(env, 500, {
      error: 'Player rank profile is temporarily unavailable.',
      code: 'public_rank_profile_failed',
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
