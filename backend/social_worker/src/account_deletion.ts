import { createRemoteJWKSet, jwtVerify } from 'jose';

import { verifyAppCheckRequest } from './app_check';

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

export type AccountDeletionEnv = {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_PROJECT_NUMBER?: string;
  ALLOWED_APP_CHECK_APP_IDS?: string;
  REQUIRE_APP_CHECK?: string;
};

export class AccountDeletionError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

export function isAccountDeletionPath(pathname: string): boolean {
  return pathname === '/v1/me/delete';
}

export async function deletePlayerAccountData(
  request: Request,
  env: AccountDeletionEnv,
): Promise<{ deleted: true }> {
  if (request.method !== 'POST') {
    throw new AccountDeletionError(405, 'Method not allowed.', 'method_not_allowed');
  }
  await verifyAppCheckRequest(request, env);
  const uid = await authenticateUid(request, env);
  const player = await env.DB.prepare(
    'SELECT id FROM players WHERE firebase_uid = ? LIMIT 1',
  )
    .bind(uid)
    .first<{ id: string }>();

  if (!player) {
    const tombstone = await env.DB.prepare(
      'SELECT 1 FROM deleted_accounts WHERE firebase_uid = ? LIMIT 1',
    )
      .bind(uid)
      .first();
    if (tombstone) return { deleted: true };
    throw new AccountDeletionError(404, 'Player profile was not found.', 'player_not_found');
  }

  const active = await env.DB.prepare(
    `SELECT id FROM matches
     WHERE (player_a_id = ? OR player_b_id = ?)
       AND status IN ('waiting', 'countdown', 'active', 'paused')
     LIMIT 1`,
  )
    .bind(player.id, player.id)
    .first<{ id: string }>();
  if (active) {
    throw new AccountDeletionError(
      409,
      'Finish or forfeit the active online match before deleting the account.',
      'active_match_exists',
    );
  }

  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO deleted_accounts (
         firebase_uid, player_id, requested_at, completed_at, reason
       ) VALUES (?, ?, ?, ?, 'user_request')
       ON CONFLICT(firebase_uid) DO UPDATE SET
         player_id = excluded.player_id,
         completed_at = excluded.completed_at`,
    ).bind(uid, player.id, now, now),
    env.DB.prepare('DELETE FROM players WHERE id = ?').bind(player.id),
  ]);
  return { deleted: true };
}

async function authenticateUid(
  request: Request,
  env: AccountDeletionEnv,
): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) {
    throw new AccountDeletionError(401, 'Missing bearer token.', 'missing_token');
  }
  const token = header.slice(7).trim();
  if (!token) {
    throw new AccountDeletionError(401, 'Missing bearer token.', 'missing_token');
  }

  const issuer = `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`;
  try {
    const result = await jwtVerify(token, FIREBASE_JWKS, {
      algorithms: ['RS256'],
      issuer,
      audience: env.FIREBASE_PROJECT_ID,
    });
    if (!result.payload.sub) throw new Error('Missing subject');
    return result.payload.sub;
  } catch {
    throw new AccountDeletionError(
      401,
      'Invalid or expired player token.',
      'invalid_token',
    );
  }
}
