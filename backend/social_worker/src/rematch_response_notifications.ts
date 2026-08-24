import { sendPlayerPush, type PushEnv } from './push_notifications';

type JsonObject = Record<string, unknown>;

type RematchResponseEnv = PushEnv & {
  ALLOWED_ORIGIN?: string;
};

type LegacyFetch = (
  request: Request,
  env: RematchResponseEnv,
  ctx: ExecutionContext,
) => Promise<Response>;

export function isRematchResponseRoute(pathname: string): boolean {
  return /^\/v1\/rematches\/[^/]+\/respond$/.test(pathname);
}

export async function handleRematchResponseNotificationRequest(
  request: Request,
  env: RematchResponseEnv,
  ctx: ExecutionContext,
  legacyFetch: LegacyFetch,
): Promise<Response> {
  const response = await legacyFetch(request, env, ctx);
  if (!response.ok || request.method !== 'POST') return response;

  const clone = response.clone();
  ctx.waitUntil(notifyOriginalSender(env, clone));
  return response;
}

async function notifyOriginalSender(
  env: RematchResponseEnv,
  response: Response,
): Promise<void> {
  try {
    const body = objectValue(await response.json());
    const rematchId = stringValue(body.id);
    const status = stringValue(body.status);
    const roomId = stringValue(body.roomId) ?? '';
    const sender = objectValue(body.sender);
    const recipient = objectValue(body.recipient);
    const senderPublicId = stringValue(sender.publicId);
    const responderName = stringValue(recipient.displayName) ?? 'Your opponent';
    if (
      rematchId == null ||
      senderPublicId == null ||
      (status !== 'accepted' && status !== 'declined')
    ) {
      return;
    }

    const player = await env.DB.prepare(
      'SELECT id FROM players WHERE public_id = ? LIMIT 1',
    )
      .bind(senderPublicId)
      .first<{ id: string }>();
    if (!player) return;

    await sendPlayerPush(env, player.id, {
      title: status === 'accepted' ? 'Rematch accepted' : 'Rematch declined',
      body: status === 'accepted'
        ? `${responderName} accepted. Your rematch room is ready.`
        : `${responderName} declined the rematch.`,
      tag: `rematch_response_${rematchId}`,
      // Reuse the existing accepted-room response envelope so every client
      // version that understands challenge_response can navigate directly to
      // PreMatchReadyScreen. rematchId remains available for diagnostics.
      data: {
        type: 'challenge_response',
        challengeId: rematchId,
        rematchId,
        status,
        roomId,
      },
    });
  } catch (error) {
    console.error('Rematch response push failed', error);
  }
}

function objectValue(value: unknown): JsonObject {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    ? (value as JsonObject)
    : {};
}

function stringValue(value: unknown): string | null {
  const text = typeof value === 'string' ? value.trim() : '';
  return text.length > 0 ? text : null;
}
