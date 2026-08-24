import { createRemoteJWKSet, jwtVerify } from 'jose';

import { AppCheckError, verifyAppCheckRequest } from './app_check';

export type RankCountryFlagEnv = {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
  ALLOWED_ORIGIN?: string;
};

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
);

const ISO_COUNTRY_CODES = new Set(
  `AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW`.split(' '),
);

class RankCountryFlagError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

type PlayerCountryRow = {
  id: string;
  public_id: string;
  country_code: string | null;
  country_flag_visible: number;
};

export function isRankCountryFlagRoute(pathname: string): boolean {
  return (
    pathname === '/v1/me/rank-country' ||
    pathname === '/v1/competitive/rank-country-flags'
  );
}

export async function handleRankCountryFlagRequest(
  request: Request,
  env: RankCountryFlagEnv,
): Promise<Response> {
  try {
    await verifyAppCheckRequest(request, env);
    const uid = await authenticateFirebase(request, env);
    await ensureCountryPreferenceSchema(env);
    const player = await playerForUid(env, uid);
    if (!player) {
      throw new RankCountryFlagError(
        404,
        'Player profile not found. Open the online profile once and try again.',
        'player_not_found',
      );
    }

    const url = new URL(request.url);
    if (url.pathname === '/v1/me/rank-country') {
      if (request.method === 'GET') {
        return json(env, 200, countryPreferenceJson(player));
      }
      if (request.method === 'PUT') {
        const body = await readJson(request);
        const countryCode = body.countryCode == null
          ? normalizeCountryCode(player.country_code)
          : validateCountryCode(String(body.countryCode));
        const flagVisible = body.countryFlagVisible == null
          ? player.country_flag_visible !== 0
          : body.countryFlagVisible === true;
        const now = new Date().toISOString();
        await env.DB.batch([
          env.DB.prepare(
            `UPDATE players SET country_code = ?, updated_at = ? WHERE id = ?`,
          ).bind(countryCode, now, player.id),
          env.DB.prepare(
            `INSERT INTO player_country_preferences (
               player_id, country_flag_visible, updated_at
             ) VALUES (?, ?, ?)
             ON CONFLICT(player_id) DO UPDATE SET
               country_flag_visible = excluded.country_flag_visible,
               updated_at = excluded.updated_at`,
          ).bind(player.id, flagVisible ? 1 : 0, now),
        ]);
        const updated = await playerById(env, player.id);
        return json(env, 200, countryPreferenceJson(updated ?? player));
      }
      return json(env, 405, {
        error: 'Method not allowed.',
        code: 'method_not_allowed',
      });
    }

    if (
      url.pathname === '/v1/competitive/rank-country-flags' &&
      request.method === 'GET'
    ) {
      const rawLimit = Number(url.searchParams.get('limit') ?? '50');
      const limit = Number.isFinite(rawLimit)
        ? Math.max(1, Math.min(100, Math.trunc(rawLimit)))
        : 50;
      return json(env, 200, await leaderboardCountryFlags(env, player.id, limit));
    }

    return json(env, 405, {
      error: 'Method not allowed.',
      code: 'method_not_allowed',
    });
  } catch (error) {
    if (error instanceof AppCheckError) {
      return json(env, 403, { error: error.message, code: error.code });
    }
    if (error instanceof RankCountryFlagError) {
      return json(env, error.status, { error: error.message, code: error.code });
    }
    console.error('rank_country_flag_route_failed', error);
    return json(env, 500, {
      error: 'Country flag settings are temporarily unavailable.',
      code: 'country_flag_failed',
    });
  }
}

async function leaderboardCountryFlags(
  env: RankCountryFlagEnv,
  viewerId: string,
  limit: number,
): Promise<Record<string, unknown>> {
  const rows = await env.DB.prepare(
    `SELECT p.public_id, p.country_code,
            COALESCE(cp.country_flag_visible, 1) AS country_flag_visible
     FROM player_rank_progression rp
     JOIN players p ON p.id = rp.player_id
     LEFT JOIN player_country_preferences cp ON cp.player_id = p.id
     WHERE rp.ranked_games > 0
     ORDER BY rp.rank_points DESC, rp.ranked_games DESC, rp.updated_at ASC, rp.player_id ASC
     LIMIT ?`,
  )
    .bind(limit)
    .all<Record<string, unknown>>();

  return {
    entries: rows.results.map((row) => {
      const visible = Number(row.country_flag_visible ?? 1) !== 0;
      return {
        publicId: row.public_id,
        // Never expose a hidden country through the public ladder response.
        countryCode: visible ? normalizeCountryCode(row.country_code) : null,
      };
    }),
  };
}

function countryPreferenceJson(row: PlayerCountryRow): Record<string, unknown> {
  return {
    countryCode: normalizeCountryCode(row.country_code),
    countryFlagVisible: row.country_flag_visible !== 0,
  };
}

function validateCountryCode(value: string): string | null {
  const code = value.trim().toUpperCase();
  if (code === '') return null;
  if (!ISO_COUNTRY_CODES.has(code)) {
    throw new RankCountryFlagError(
      400,
      'Select a valid country or region.',
      'invalid_country',
    );
  }
  return code;
}

function normalizeCountryCode(value: unknown): string | null {
  if (value == null) return null;
  const code = String(value).trim().toUpperCase();
  return ISO_COUNTRY_CODES.has(code) ? code : null;
}

async function ensureCountryPreferenceSchema(
  env: RankCountryFlagEnv,
): Promise<void> {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS player_country_preferences (
       player_id TEXT PRIMARY KEY,
       country_flag_visible INTEGER NOT NULL DEFAULT 1
         CHECK(country_flag_visible IN (0, 1)),
       updated_at TEXT NOT NULL,
       FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
     )`,
  ).run();
}

async function playerForUid(
  env: RankCountryFlagEnv,
  uid: string,
): Promise<PlayerCountryRow | null> {
  return env.DB.prepare(
    `SELECT p.id, p.public_id, p.country_code,
            COALESCE(cp.country_flag_visible, 1) AS country_flag_visible
     FROM players p
     LEFT JOIN player_country_preferences cp ON cp.player_id = p.id
     WHERE p.firebase_uid = ? LIMIT 1`,
  )
    .bind(uid)
    .first<PlayerCountryRow>();
}

async function playerById(
  env: RankCountryFlagEnv,
  playerId: string,
): Promise<PlayerCountryRow | null> {
  return env.DB.prepare(
    `SELECT p.id, p.public_id, p.country_code,
            COALESCE(cp.country_flag_visible, 1) AS country_flag_visible
     FROM players p
     LEFT JOIN player_country_preferences cp ON cp.player_id = p.id
     WHERE p.id = ? LIMIT 1`,
  )
    .bind(playerId)
    .first<PlayerCountryRow>();
}

async function authenticateFirebase(
  request: Request,
  env: RankCountryFlagEnv,
): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) {
    throw new RankCountryFlagError(401, 'Missing bearer token.', 'missing_auth');
  }
  const token = header.slice(7).trim();
  if (!token) {
    throw new RankCountryFlagError(401, 'Missing bearer token.', 'missing_auth');
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
    throw new RankCountryFlagError(
      401,
      'Invalid or expired Firebase ID token.',
      'invalid_auth',
    );
  }
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('Invalid object.');
    }
    return value as Record<string, unknown>;
  } catch {
    throw new RankCountryFlagError(400, 'Invalid JSON body.', 'invalid_json');
  }
}

function json(
  env: RankCountryFlagEnv,
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
