import {
  duelVariantConfig,
  normalizeDuelVariant,
  type DuelVariant,
} from './sudoku_variant';
import { ensureVariantSchema } from './variant_schema';
import type { VariantMatchmakingEnv } from './variant_matchmaking';

type LegacyFetch = (
  request: Request,
  env: VariantMatchmakingEnv,
  ctx: ExecutionContext,
) => Promise<Response>;

type JsonObject = Record<string, unknown>;

type ChallengeVariantRow = {
  variant: string;
  room_id: string | null;
};

export function isVariantChallengeRoute(pathname: string): boolean {
  return (
    pathname === '/v1/challenges' ||
    /^\/v1\/challenges\/[^/]+$/.test(pathname) ||
    /^\/v1\/challenges\/[^/]+\/respond$/.test(pathname)
  );
}

export async function handleVariantChallengeRequest(
  request: Request,
  env: VariantMatchmakingEnv,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
): Promise<Response> {
  await ensureVariantSchema(env);
  const url = new URL(request.url);
  const challengeId = challengeIdFromPath(url.pathname);
  let requestedVariant: DuelVariant | null = null;
  let action: string | null = null;

  if (url.pathname === '/v1/challenges' && request.method === 'POST') {
    const body = await readJsonClone(request);
    try {
      requestedVariant = normalizeDuelVariant(body.variant, 'classic9');
    } catch (_) {
      return json(env, 400, { error: 'Invalid Sudoku variant.' });
    }
  }

  if (
    challengeId != null &&
    url.pathname.endsWith('/respond') &&
    request.method === 'POST'
  ) {
    const body = await readJsonClone(request);
    action = typeof body.action === 'string' ? body.action : null;
    if (action === 'accept') {
      const row = await loadChallengeVariant(env, challengeId);
      if (row != null && row.variant === 'classic16') {
        const roomId = row.room_id?.startsWith('classic16:') == true
          ? row.room_id
          : `classic16:${crypto.randomUUID()}`;
        await env.DB.prepare(
          `UPDATE challenges SET room_id = ?, updated_at = ?
           WHERE id = ? AND status IN ('pending', 'accepted')`,
        )
          .bind(roomId, new Date().toISOString(), challengeId)
          .run();
      }
    }
  }

  const response = await legacyFetch(request, env, ctx);
  if (!response.ok || response.status === 204) return response;

  const payload = await responseObject(response);

  if (
    url.pathname === '/v1/challenges' &&
    request.method === 'POST' &&
    requestedVariant != null
  ) {
    const id = stringValue(payload.id);
    if (id != null) {
      await env.DB.prepare(
        `UPDATE challenges SET variant = ?, updated_at = ? WHERE id = ?`,
      )
        .bind(requestedVariant, new Date().toISOString(), id)
        .run();
      return jsonFromLegacy(
        response,
        await augmentChallenge(env, payload, id),
      );
    }
  }

  if (url.pathname === '/v1/challenges' && request.method === 'GET') {
    const values = Array.isArray(payload.challenges)
      ? payload.challenges
      : [];
    const challenges = await Promise.all(
      values.map(async (value) => {
        const item = objectValue(value);
        const id = stringValue(item.id);
        return id == null ? item : augmentChallenge(env, item, id);
      }),
    );
    return jsonFromLegacy(response, { ...payload, challenges });
  }

  if (challengeId != null) {
    const augmented = await augmentChallenge(env, payload, challengeId);
    if (action === 'accept') {
      const metadata = await challengeMetadata(env, challengeId);
      const roomId = stringValue(augmented.roomId);
      if (roomId != null) {
        await env.DB.prepare(
          `UPDATE matches
           SET variant = ?, board_size = ?, cell_count = ?, updated_at = ?
           WHERE challenge_id = ? OR room_id = ?`,
        )
          .bind(
            metadata.variant,
            metadata.boardSize,
            metadata.cellCount,
            new Date().toISOString(),
            challengeId,
            roomId,
          )
          .run();
      }
    }
    return jsonFromLegacy(response, augmented);
  }

  return jsonFromLegacy(response, payload);
}

async function augmentChallenge(
  env: VariantMatchmakingEnv,
  payload: JsonObject,
  challengeId: string,
): Promise<JsonObject> {
  const metadata = await challengeMetadata(env, challengeId);
  return {
    ...payload,
    variant: metadata.variant,
    boardSize: metadata.boardSize,
    cellCount: metadata.cellCount,
  };
}

async function challengeMetadata(
  env: VariantMatchmakingEnv,
  challengeId: string,
): Promise<{
  variant: DuelVariant;
  boardSize: number;
  cellCount: number;
}> {
  const row = await loadChallengeVariant(env, challengeId);
  const variant = normalizeDuelVariant(row?.variant, 'classic9');
  const config = duelVariantConfig(variant);
  return {
    variant,
    boardSize: config.boardSize,
    cellCount: config.cellCount,
  };
}

async function loadChallengeVariant(
  env: VariantMatchmakingEnv,
  challengeId: string,
): Promise<ChallengeVariantRow | null> {
  return env.DB.prepare(
    `SELECT variant, room_id FROM challenges WHERE id = ? LIMIT 1`,
  )
    .bind(challengeId)
    .first<ChallengeVariantRow>();
}

function challengeIdFromPath(pathname: string): string | null {
  const parts = pathname.split('/').filter(Boolean);
  if (parts.length < 3 || parts[0] !== 'v1' || parts[1] !== 'challenges') {
    return null;
  }
  return parts[2] || null;
}

async function readJsonClone(request: Request): Promise<JsonObject> {
  try {
    return objectValue(await request.clone().json());
  } catch (_) {
    return {};
  }
}

async function responseObject(response: Response): Promise<JsonObject> {
  try {
    return objectValue(await response.json());
  } catch (_) {
    return {};
  }
}

function objectValue(value: unknown): JsonObject {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonObject
    : {};
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function jsonFromLegacy(response: Response, payload: JsonObject): Response {
  const headers = new Headers(response.headers);
  headers.set('content-type', 'application/json; charset=utf-8');
  return new Response(JSON.stringify(payload), {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function json(
  env: VariantMatchmakingEnv,
  status: number,
  payload: JsonObject,
): Response {
  const headers = new Headers({
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  if (env.ALLOWED_ORIGIN) {
    headers.set('access-control-allow-origin', env.ALLOWED_ORIGIN);
  }
  return new Response(JSON.stringify(payload), { status, headers });
}
