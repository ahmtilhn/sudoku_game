import { describe, expect, it } from 'vitest';

import { nextAlarmAt } from '../src/cost_retention';
import {
  DISCONNECT_GRACE_MS,
  MAX_GRACE_BUDGET_MS,
  applyDueDeadlines,
  applyReady,
  applyScreenLoaded,
  createInitialDuelState,
  markConnected,
  markDisconnected,
} from '../src/online_duel';

function state() {
  return createInitialDuelState({
    roomId: 'room-grace',
    matchId: 'match-grace',
    challengeId: null,
    mode: 'ranked',
    difficulty: 'medium',
    playerA: {
      id: 'a',
      publicId: 'A',
      username: 'alice',
      displayName: 'Alice',
      avatarKey: 'default',
    },
    playerB: {
      id: 'b',
      publicId: 'B',
      username: 'bob',
      displayName: 'Bob',
      avatarKey: 'default',
    },
    now: 1_000,
    randomBytes: new Uint8Array([
      1, 2, 3, 4, 5, 6, 7, 8,
      9, 1, 2, 3, 4, 5, 6, 7,
    ]),
  });
}

function startDuel(duel: ReturnType<typeof state>, now = 1_000) {
  markConnected(duel, 'A', now + 1);
  markConnected(duel, 'B', now + 2);
  applyScreenLoaded(duel, 'A', now + 3);
  applyScreenLoaded(duel, 'B', now + 4);
  applyReady(duel, 'A', now + 5);
  applyReady(duel, 'B', now + 6);
}

describe('cumulative disconnect grace budget', () => {
  it('charges only the actual disconnected time when a player reconnects', () => {
    const duel = state();
    startDuel(duel);
    const originalTurnDeadline = duel.turnDeadline!;

    markDisconnected(duel, 'A', 5_000);
    expect(duel.playerA.disconnectDeadline).toBe(5_000 + DISCONNECT_GRACE_MS);

    markConnected(duel, 'A', 20_000);

    expect(duel.playerA.graceRemainingMs).toBe(MAX_GRACE_BUDGET_MS - 15_000);
    expect(duel.status).toBe('active');
    expect(duel.turnDeadline).toBe(20_000 + (originalTurnDeadline - 5_000));
  });

  it('caps each disconnect at 30 seconds and the whole match at 60 seconds', () => {
    const duel = state();
    startDuel(duel);

    markDisconnected(duel, 'A', 5_000);
    markConnected(duel, 'A', 34_000);
    expect(duel.playerA.graceRemainingMs).toBe(31_000);

    markDisconnected(duel, 'A', 40_000);
    expect(duel.playerA.disconnectDeadline).toBe(70_000);
    markConnected(duel, 'A', 69_000);
    expect(duel.playerA.graceRemainingMs).toBe(2_000);

    markDisconnected(duel, 'A', 75_000);
    expect(duel.playerA.disconnectDeadline).toBe(77_000);

    applyDueDeadlines(duel, 76_999);
    expect(duel.status).toBe('paused');

    applyDueDeadlines(duel, 77_000);
    expect(duel.status).toBe('forfeited');
    expect(duel.winnerSeat).toBe('B');
    expect(duel.finishReason).toBe('disconnect_forfeit');
  });

  it('keeps each player disconnect budget independent', () => {
    const duel = state();
    startDuel(duel);

    markDisconnected(duel, 'A', 5_000);
    markConnected(duel, 'A', 15_000);

    expect(duel.playerA.graceRemainingMs).toBe(50_000);
    expect(duel.playerB.graceRemainingMs).toBe(MAX_GRACE_BUDGET_MS);

    markDisconnected(duel, 'B', 20_000);
    expect(duel.playerB.disconnectDeadline).toBe(20_000 + DISCONNECT_GRACE_MS);
  });

  it('does not refresh the reconnect deadline for duplicate disconnect events', () => {
    const duel = state();
    startDuel(duel);

    markDisconnected(duel, 'A', 5_000);
    const firstDeadline = duel.playerA.disconnectDeadline;
    const firstDisconnectedAt = duel.playerA.lastSeenAt;

    markDisconnected(duel, 'A', 10_000);

    expect(duel.playerA.disconnectDeadline).toBe(firstDeadline);
    expect(duel.playerA.lastSeenAt).toBe(firstDisconnectedAt);
  });

  it('makes an exhausted cumulative budget immediately due for forfeit', () => {
    const duel = state();
    startDuel(duel);
    duel.playerA.graceRemainingMs = 0;

    markDisconnected(duel, 'A', 5_000);

    expect(duel.playerA.disconnectDeadline).toBe(5_000);
    applyDueDeadlines(duel, 5_000);

    expect(duel.status).toBe('forfeited');
    expect(duel.winnerSeat).toBe('B');
    expect(duel.finishReason).toBe('disconnect_forfeit');
  });

  it('schedules an already-due disconnect deadline instead of dropping it', () => {
    expect(
      nextAlarmAt(
        {
          status: 'paused',
          lobbyDeadline: null,
          readyDeadline: null,
          turnDeadline: null,
          playerADisconnectDeadline: 5_000,
          playerBDisconnectDeadline: null,
          finishedAt: null,
          settled: false,
        },
        5_010,
      ),
    ).toBe(5_011);
  });

  it('restores the full budget for legacy stored state that lacks the field', () => {
    const duel = state();
    startDuel(duel);
    delete (duel.playerA as { graceRemainingMs?: number }).graceRemainingMs;

    markDisconnected(duel, 'A', 5_000);
    expect(duel.playerA.disconnectDeadline).toBe(35_000);

    markConnected(duel, 'A', 15_000);
    expect(duel.playerA.graceRemainingMs).toBe(50_000);
  });

  it('does not spend disconnect budget before the match has started', () => {
    const duel = state();

    markConnected(duel, 'A', 1_001);
    markDisconnected(duel, 'A', 2_000);
    markConnected(duel, 'A', 5_000);

    expect(duel.startedAt).toBeNull();
    expect(duel.playerA.disconnectDeadline).toBeNull();
    expect(duel.playerA.graceRemainingMs).toBe(MAX_GRACE_BUDGET_MS);
  });
});
