import {
  READY_DEADLINE_MS,
  TURN_DURATION_MS,
  type DuelState,
  type PublicEvent,
  type Seat,
  event,
  seatFor,
} from './online_duel_model';
import { readinessPayload } from './online_duel_view';

/// Ready-screen and game-screen loading policy.
///
/// Phase 1: both clients load the Ready screen -> one shared 10 second
/// readyDeadline is created.
/// Phase 2: when that deadline expires, the deadline policy moves the room to
/// active but deliberately leaves startedAt/turnDeadline null and resets both
/// screenLoaded flags.
/// Phase 3: both Sudoku board clients report screenLoaded -> only then are
/// startedAt and the first turnDeadline armed.
export function applyReady(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent[] {
  if (state.status === 'active' || state.finishedAt !== null) {
    return [event(state, 'player_ready', now, readinessPayload(state, { seat }))];
  }

  const current = seatFor(state, seat);
  if (!current.ready) {
    current.ready = true;
    state.revision++;
  }

  const readyWindowEvents = maybeOpenReadyWindow(state, now);
  return [
    event(state, 'player_ready', now, readinessPayload(state, { seat })),
    ...readyWindowEvents,
  ];
}

export function applyScreenLoaded(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent[] {
  if (state.finishedAt !== null) {
    return [event(state, 'screen_loaded', now, readinessPayload(state, { seat }))];
  }

  const current = seatFor(state, seat);
  if (!current.screenLoaded) {
    current.screenLoaded = true;
    state.revision++;
  }

  const loaded = event(
    state,
    'screen_loaded',
    now,
    readinessPayload(state, { seat }),
  );

  if (state.status === 'active') {
    return [loaded, ...maybeArmGameplayClock(state, now)];
  }

  const readyWindowEvents = maybeOpenReadyWindow(state, now);
  return [loaded, ...readyWindowEvents];
}

function maybeOpenReadyWindow(
  state: DuelState,
  now: number,
): PublicEvent[] {
  if (
    state.startedAt !== null ||
    state.finishedAt !== null ||
    state.readyDeadline !== null ||
    !bothConnectedAndLoaded(state)
  ) {
    return [];
  }

  state.status = 'ready_window';
  state.lobbyDeadline = null;
  state.readyDeadline = now + READY_DEADLINE_MS;
  state.revision++;

  return [
    event(state, 'ready_window_started', now, readinessPayload(state)),
  ];
}

function maybeArmGameplayClock(
  state: DuelState,
  now: number,
): PublicEvent[] {
  if (
    state.status !== 'active' ||
    state.startedAt !== null ||
    state.finishedAt !== null ||
    !bothConnectedAndLoaded(state)
  ) {
    return [];
  }

  state.startedAt = now;
  state.turnStartedAt = now;
  state.turnDeadline = now + TURN_DURATION_MS;
  state.revision++;

  const started = event(state, 'match_started', now, {});
  return [
    started,
    {
      ...started,
      type: 'game_started',
      eventId: `${state.roomId}:${state.revision}:game_started`,
    },
  ];
}

function bothConnectedAndLoaded(state: DuelState): boolean {
  return (
    state.playerA.connected &&
    state.playerB.connected &&
    state.playerA.screenLoaded &&
    state.playerB.screenLoaded
  );
}
