import {
  READY_DEADLINE_MS,
  type DuelState,
  type PublicEvent,
  type Seat,
  event,
  seatFor,
} from './online_duel_model';
import { readinessPayload } from './online_duel_view';

/// Ready-screen policy for the fixed, server-authoritative pre-match countdown.
///
/// Players may mark themselves ready at any point, but readiness no longer
/// skips the 10-second ready window. The actual transition to `active` remains
/// owned by `applyDueDeadlines`, so both clients see the same countdown and the
/// match begins only when the authoritative ready deadline expires.
export function applyReady(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent[] {
  if (state.status === 'active' || state.finishedAt !== null) {
    return [event(state, 'player_ready', now, { seat })];
  }

  const current = seatFor(state, seat);
  if (!current.ready) {
    current.ready = true;
    state.revision++;
  }

  const events = [event(state, 'player_ready', now, { seat })];
  events.push(...maybeOpenReadyWindow(state, now));
  return events;
}

export function applyScreenLoaded(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent[] {
  if (state.status === 'active' || state.finishedAt !== null) {
    return [event(state, 'screen_loaded', now, { seat })];
  }

  const current = seatFor(state, seat);
  if (!current.screenLoaded) {
    current.screenLoaded = true;
    state.revision++;
  }

  const events = [event(state, 'screen_loaded', now, { seat })];
  events.push(...maybeOpenReadyWindow(state, now));
  return events;
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

function bothConnectedAndLoaded(state: DuelState): boolean {
  return (
    state.playerA.connected &&
    state.playerB.connected &&
    state.playerA.screenLoaded &&
    state.playerB.screenLoaded
  );
}
