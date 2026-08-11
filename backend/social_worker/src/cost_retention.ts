export type RetentionEnv = {
  DB: D1Database;
};

export type CleanupResult = {
  table: string;
  deleted: number;
};

export type CleanupPlanItem = {
  table: string;
  sql: string;
  bindings: unknown[];
  retention: string;
};

export const DEFAULT_CLEANUP_LIMIT = 500;
export const TERMINAL_ROOM_STORAGE_GRACE_MS = 15 * 60 * 1000;

export function shouldPersistClientMessage(input: {
  type: string;
  beforeRevision: number;
  afterRevision: number;
}): boolean {
  if (input.type === 'ping' || input.type === 'request_snapshot') return false;
  return input.afterRevision !== input.beforeRevision;
}

export function shouldUpdateAlarm(
  currentAlarmAt: number | null,
  nextAlarmAt: number | null,
): boolean {
  return currentAlarmAt !== nextAlarmAt;
}

export function nextAlarmAt(
  input: {
    status: string;
    lobbyDeadline?: number | null;
    readyDeadline: number | null;
    turnDeadline: number | null;
    playerADisconnectDeadline: number | null;
    playerBDisconnectDeadline: number | null;
    finishedAt?: number | null;
    settled?: boolean;
  },
  nowMs: number,
): number | null {
  const deadlines = [
    input.status === 'waiting' ? input.lobbyDeadline ?? null : null,
    input.status === 'ready_window' ? input.readyDeadline : null,
    input.status === 'active' ? input.turnDeadline : null,
    input.playerADisconnectDeadline,
    input.playerBDisconnectDeadline,
    isTerminalRoom(input.status) && input.settled === true && input.finishedAt
      ? input.finishedAt + TERMINAL_ROOM_STORAGE_GRACE_MS
      : null,
  ].filter((value): value is number => typeof value === 'number' && value > nowMs);
  return deadlines.length === 0 ? null : Math.min(...deadlines);
}

export function terminalRoomCleanupDue(input: {
  status: string;
  settled: boolean;
  finishedAt: number | null;
}, nowMs: number): boolean {
  return (
    isTerminalRoom(input.status) &&
    input.settled &&
    input.finishedAt !== null &&
    nowMs >= input.finishedAt + TERMINAL_ROOM_STORAGE_GRACE_MS
  );
}

export function buildRetentionCleanupPlan(
  now = new Date(),
  limit = DEFAULT_CLEANUP_LIMIT,
): CleanupPlanItem[] {
  const clampedLimit = Math.max(1, Math.min(1000, Math.trunc(limit)));
  const rateLimitBefore = unixSecondsBefore(now, 48);
  const sevenDaysAgo = isoHoursBefore(now, 24 * 7);
  const thirtyDaysAgo = isoHoursBefore(now, 24 * 30);

  return [
    {
      table: 'request_limits',
      retention: '48 hours',
      sql: `DELETE FROM request_limits
            WHERE key IN (
              SELECT key FROM request_limits
              WHERE window_started_at < ?
              LIMIT ?
            )`,
      bindings: [rateLimitBefore, clampedLimit],
    },
    {
      table: 'device_tokens',
      retention: '7 days disabled',
      sql: `DELETE FROM device_tokens
            WHERE id IN (
              SELECT id FROM device_tokens
              WHERE enabled = 0 AND updated_at < ?
              LIMIT ?
            )`,
      bindings: [sevenDaysAgo, clampedLimit],
    },
    {
      table: 'reward_claims',
      retention: '7 days unused ad preparation token',
      sql: `DELETE FROM reward_claims
            WHERE id IN (
              SELECT id FROM reward_claims
              WHERE status IN ('prepared', 'expired')
                AND expires_at IS NOT NULL
                AND expires_at < ?
              LIMIT ?
            )`,
      bindings: [sevenDaysAgo, clampedLimit],
    },
    {
      table: 'challenges',
      retention: '30 days terminal challenge',
      sql: `DELETE FROM challenges
            WHERE id IN (
              SELECT id FROM challenges
              WHERE status IN ('declined', 'expired', 'cancelled', 'completed')
                AND updated_at < ?
              LIMIT ?
            )`,
      bindings: [thirtyDaysAgo, clampedLimit],
    },
    {
      table: 'rematch_invitations',
      retention: '30 days terminal rematch',
      sql: `DELETE FROM rematch_invitations
            WHERE id IN (
              SELECT id FROM rematch_invitations
              WHERE status IN ('accepted', 'declined', 'expired', 'cancelled', 'insufficient_coins')
                AND updated_at < ?
              LIMIT ?
            )`,
      bindings: [thirtyDaysAgo, clampedLimit],
    },
    {
      table: 'match_audit',
      retention: '30 days transient audit',
      sql: `DELETE FROM match_audit
            WHERE rowid IN (
              SELECT rowid FROM match_audit
              WHERE event_timestamp < ?
              LIMIT ?
            )`,
      bindings: [thirtyDaysAgo, clampedLimit],
    },
  ];
}

export async function runRetentionCleanup(
  env: RetentionEnv,
  now = new Date(),
  limit = DEFAULT_CLEANUP_LIMIT,
): Promise<CleanupResult[]> {
  const results: CleanupResult[] = [];
  for (const item of buildRetentionCleanupPlan(now, limit)) {
    const result = await env.DB.prepare(item.sql).bind(...item.bindings).run();
    results.push({
      table: item.table,
      deleted: Number(result.meta.changes ?? 0),
    });
  }
  return results;
}

function isoHoursBefore(now: Date, hours: number): string {
  return new Date(now.getTime() - hours * 60 * 60 * 1000).toISOString();
}

function unixSecondsBefore(now: Date, hours: number): number {
  return Math.floor((now.getTime() - hours * 60 * 60 * 1000) / 1000);
}

function isTerminalRoom(status: string): boolean {
  return status === 'completed' || status === 'forfeited' || status === 'cancelled';
}
