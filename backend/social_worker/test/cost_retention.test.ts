import { describe, expect, it } from 'vitest';

import {
  TERMINAL_ROOM_STORAGE_GRACE_MS,
  buildRetentionCleanupPlan,
  nextAlarmAt,
  shouldPersistClientMessage,
  shouldUpdateAlarm,
  terminalRoomCleanupDue,
} from '../src/cost_retention';
import {
  compareLeaderboardRows,
  decodeLeaderboardCursor,
  encodeLeaderboardCursor,
} from '../src/competitive';

describe('cost and retention guardrails', () => {
  it('does not persist no-op ping or snapshot requests', () => {
    expect(
      shouldPersistClientMessage({
        type: 'ping',
        beforeRevision: 10,
        afterRevision: 10,
      }),
    ).toBe(false);
    expect(
      shouldPersistClientMessage({
        type: 'request_snapshot',
        beforeRevision: 10,
        afterRevision: 10,
      }),
    ).toBe(false);
  });

  it('persists mutating moves only when revision changes', () => {
    expect(
      shouldPersistClientMessage({
        type: 'move',
        beforeRevision: 10,
        afterRevision: 12,
      }),
    ).toBe(true);
    expect(
      shouldPersistClientMessage({
        type: 'move',
        beforeRevision: 10,
        afterRevision: 10,
      }),
    ).toBe(false);
  });

  it('changes alarms only when the required deadline changes', () => {
    expect(shouldUpdateAlarm(123, 123)).toBe(false);
    expect(shouldUpdateAlarm(123, 456)).toBe(true);
    expect(shouldUpdateAlarm(123, null)).toBe(true);
  });

  it('computes the earliest active room deadline', () => {
    expect(
      nextAlarmAt(
        {
          status: 'active',
          readyDeadline: 50,
          turnDeadline: 200,
          playerADisconnectDeadline: 150,
          playerBDisconnectDeadline: null,
        },
        100,
      ),
    ).toBe(150);
  });

  it('keeps settled room storage through the reconnect grace period', () => {
    const finishedAt = Date.parse('2026-07-28T12:00:00.000Z');
    expect(
      nextAlarmAt(
        {
          status: 'completed',
          readyDeadline: null,
          turnDeadline: null,
          playerADisconnectDeadline: null,
          playerBDisconnectDeadline: null,
          finishedAt,
          settled: true,
        },
        finishedAt + 1,
      ),
    ).toBe(finishedAt + TERMINAL_ROOM_STORAGE_GRACE_MS);
    expect(
      terminalRoomCleanupDue(
        { status: 'completed', settled: true, finishedAt },
        finishedAt + TERMINAL_ROOM_STORAGE_GRACE_MS - 1,
      ),
    ).toBe(false);
  });

  it('detects settled room cleanup after grace and keeps duplicate cleanup idempotent', () => {
    const finishedAt = Date.parse('2026-07-28T12:00:00.000Z');
    const cleanupAt = finishedAt + TERMINAL_ROOM_STORAGE_GRACE_MS;
    expect(
      terminalRoomCleanupDue(
        { status: 'forfeited', settled: true, finishedAt },
        cleanupAt,
      ),
    ).toBe(true);
    expect(
      terminalRoomCleanupDue(
        { status: 'forfeited', settled: true, finishedAt: null },
        cleanupAt,
      ),
    ).toBe(false);
  });

  it('keeps cursor pagination deterministic', () => {
    const sorted = [
      {
        playerId: 'b',
        rating: 1400,
        gamesPlayed: 10,
        wins: 6,
        draws: 1,
        updatedAt: '2026-01-01T00:00:01.000Z',
      },
      {
        playerId: 'a',
        rating: 1400,
        gamesPlayed: 10,
        wins: 6,
        draws: 1,
        updatedAt: '2026-01-01T00:00:01.000Z',
      },
    ].sort(compareLeaderboardRows);

    const cursor = encodeLeaderboardCursor(sorted[0]);
    expect(decodeLeaderboardCursor(cursor)).toEqual(sorted[0]);
    expect(sorted.map((row) => row.playerId)).toEqual(['a', 'b']);
  });

  it('keeps cleanup batch sizes bounded and active challenge data out of scope', () => {
    const plan = buildRetentionCleanupPlan(
      new Date('2026-07-28T12:00:00.000Z'),
      5000,
    );
    expect(plan.every((item) => item.bindings.at(-1) === 1000)).toBe(true);
    const challengeCleanup = plan.find((item) => item.table === 'challenges');
    expect(challengeCleanup?.sql).toContain("'completed'");
    expect(challengeCleanup?.sql).not.toContain("'pending'");
    expect(challengeCleanup?.sql).not.toContain("'accepted'");
  });
});
