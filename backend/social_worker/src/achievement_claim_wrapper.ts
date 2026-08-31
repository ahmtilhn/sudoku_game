type LegacyFetch = (request: Request) => Promise<Response>;

const CLAIM_PATH = /^\/v1\/achievements\/([^/]+)\/claim$/;

export function isAchievementClaimRoute(pathname: string): boolean {
  return CLAIM_PATH.test(pathname);
}

/// Compatibility wrapper for old clients that still POST the seven reward
/// achievement IDs after completing a local puzzle. Eligibility is no longer
/// recalculated from the classic9 compatibility columns. Instead the canonical
/// player_achievements state (filled from all online variants) decides whether
/// the claim is complete, and the automatic D1 trigger has already granted the
/// exactly-once Coin reward when that row was inserted.
export async function handleAchievementClaimRequest(
  request: Request,
  legacyFetch: LegacyFetch,
): Promise<Response> {
  if (request.method !== 'POST') return legacyFetch(request);
  const url = new URL(request.url);
  const match = CLAIM_PATH.exec(url.pathname);
  if (!match) return legacyFetch(request);
  const achievementId = decodeURIComponent(match[1] ?? '').trim();
  if (!achievementId) return legacyFetch(request);

  const listRequest = new Request(new URL('/v1/achievements', request.url), {
    method: 'GET',
    headers: request.headers,
  });
  const listResponse = await legacyFetch(listRequest);
  if (!listResponse.ok) return listResponse;

  const payload = (await listResponse.json()) as {
    achievements?: Array<{ id?: unknown; unlocked?: unknown }>;
  };
  const row = payload.achievements?.find(
    (value) => String(value.id ?? '') === achievementId,
  );
  if (!row) {
    return jsonLike(listResponse, 404, {
      error: 'Unknown achievement reward.',
      code: 'achievement_unknown',
    });
  }
  if (row.unlocked !== true) {
    return jsonLike(listResponse, 409, {
      error: 'Achievement requirement is not complete.',
      code: 'achievement_incomplete',
    });
  }

  const walletRequest = new Request(new URL('/v1/me/wallet', request.url), {
    method: 'GET',
    headers: request.headers,
  });
  return legacyFetch(walletRequest);
}

function jsonLike(
  source: Response,
  status: number,
  value: Record<string, unknown>,
): Response {
  const headers = new Headers(source.headers);
  headers.set('content-type', 'application/json; charset=utf-8');
  return new Response(JSON.stringify(value), { status, headers });
}
