import { describe, expect, it } from 'vitest';

import {
  READY_DEADLINE_MS,
  TURN_DURATION_MS,
  applyDueDeadlines,
  applyReady,
  applyScreenLoaded,
  createInitialDuelState,
  markConnected,
} from '../src/online_duel';

function state() {
  return createInitialDuelState({
    roomId: 'room-ready-countdown',
    matchId: 'match-ready-countdown',
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

describe('ready countdown', () => {
  it('delivers the authoritative deadline on the event that opens the ready window', () => {
    const duel = state();
    markConnected(duel, 'A', 1_001);
    markConnected(duel, 'B', 1_002);
    applyScreenLoaded(duel, 'A', 1_003);

    const events = applyScreenLoaded(duel, 'B', 1_004);
    const screenLoaded = events.find((event) => event.type === 'screen_loaded');
    const windowStarted = events.find(
      (event) => event.type === 'ready_window_started',
    );

    expect(screenLoaded).toBeDefined();
    expect(screenLoaded?.payload.status).toBe('ready_window');
    expect(screenLoaded?.payload.readyDeadline).toBe(
      1_004 + READY_DEADLINE_MS,
    );
    expect(screenLoaded?.payload.screenLoaded).toEqual({ A: true, B: true });
    expect(screenLoaded?.payload.presence).toEqual({ A: true, B: true });
    expect(windowStarted?.payload.readyDeadline).toBe(
      1_004 + READY_DEADLINE_MS,
    );
  });

  it('finishes Ready countdown before arming the first playable turn', () => {
    const duel = state();
    markConnected(duel, 'A', 1_001);
    markConnected(duel, 'B', 1_002);
    applyScreenLoaded(duel, 'A', 1_003);
    applyScreenLoaded(duel, 'B', 1_004);

    expect(duel.status).toBe('ready_window');
    expect(duel.readyDeadline).toBe(1_004 + READY_DEADLINE_MS);

    applyReady(duel, 'A', 1_100);
    applyReady(duel, 'B', 1_200);

    expect(duel.playerA.ready).toBe(true);
    expect(duel.playerB.ready).toBe(true);
    expect(duel.status).toBe('ready_window');
    expect(duel.startedAt).toBeNull();

    applyDueDeadlines(duel, duel.readyDeadline! - 1);
    expect(duel.status).toBe('ready_window');
    expect(duel.startedAt).toBeNull();

    const deadline = duel.readyDeadline!;
    const handoffEvents = applyDueDeadlines(duel, deadline);

    expect(duel.status).toBe('active');
    expect(duel.startedAt).toBeNull();
    expect(duel.turnStartedAt).toBeNull();
    expect(duel.turnDeadline).toBeNull();
    expect(duel.readyDeadline).toBeNull();
    expect(duel.playerA.screenLoaded).toBe(false);
    expect(duel.playerB.screenLoaded).toBe(false);
    expect(handoffEvents.map((event) => event.type)).toEqual(['snapshot']);

    applyScreenLoaded(duel, 'A', deadline + 20);
    expect(duel.startedAt).toBeNull();
    expect(duel.turnDeadline).toBeNull();

    const startAt = deadline + 40;
    const startEvents = applyScreenLoaded(duel, 'B', startAt);

    expect(duel.startedAt).toBe(startAt);
    expect(duel.turnStartedAt).toBe(startAt);
    expect(duel.turnDeadline).toBe(startAt + TURN_DURATION_MS);
    expect(startEvents.filter((event) => event.type === 'match_started')).toHaveLength(1);
    expect(startEvents.filter((event) => event.type === 'game_started')).toHaveLength(1);
  });
});
