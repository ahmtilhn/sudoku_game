import {
  DISCONNECT_GRACE_MS,
  MAX_GRACE_BUDGET_MS,
  type DuelState,
  type PublicEvent,
  type Seat,
  event,
  seatFor,
} from './online_duel_model';
import {
  markConnected as markConnectedInEngine,
  markDisconnected as markDisconnectedInEngine,
} from './online_duel_engine';
import { readinessPayload } from './online_duel_view';

/**
 * Presence policy around the authoritative duel engine.
 *
 * Each player owns a 60 second cumulative reconnect budget for the whole match.
 * A single disconnect may consume at most the normal 30 second reconnect grace.
 * Only the actual time spent disconnected is charged when the player reconnects.
 */
export function markConnected(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent {
  const current = seatFor(state, seat);
  current.graceRemainingMs = normalizedGraceRemaining(current.graceRemainingMs);

  if (
    state.startedAt !== null &&
    !current.connected &&
    current.disconnectDeadline !== null
  ) {
    const disconnectStartedAt = Math.min(now, current.lastSeenAt);
    const chargedUntil = Math.min(now, current.disconnectDeadline);
    const elapsedMs = Math.max(0, chargedUntil - disconnectStartedAt);
    current.graceRemainingMs = Math.max(
      0,
      current.graceRemainingMs - Math.min(current.graceRemainingMs, elapsedMs),
    );
  }

  return markConnectedInEngine(state, seat, now);
}

export function markDisconnected(
  state: DuelState,
  seat: Seat,
  now: number,
): PublicEvent {
  const current = seatFor(state, seat);
  current.graceRemainingMs = normalizedGraceRemaining(current.graceRemainingMs);

  const inStartedMatch =
    state.startedAt !== null &&
    (state.status === 'active' || state.status === 'paused');

  // A duplicate close notification must never restart the reconnect clock.
  if (
    inStartedMatch &&
    !current.connected &&
    current.disconnectDeadline !== null
  ) {
    current.screenLoaded = false;
    state.revision++;
    return event(
      state,
      'player_presence',
      now,
      readinessPayload(state, { seat, connected: false }),
    );
  }

  const presence = markDisconnectedInEngine(state, seat, now);

  if (inStartedMatch) {
    const allowedGraceMs = Math.min(
      DISCONNECT_GRACE_MS,
      current.graceRemainingMs,
    );

    // nextAlarmAt only schedules strictly-future deadlines. One millisecond
    // keeps a fully exhausted budget authoritative without granting a new
    // usable reconnect window.
    current.disconnectDeadline = now + Math.max(1, allowedGraceMs);
  }

  return presence;
}

function normalizedGraceRemaining(value: number): number {
  if (!Number.isFinite(value)) return MAX_GRACE_BUDGET_MS;
  return Math.max(0, Math.min(MAX_GRACE_BUDGET_MS, Math.trunc(value)));
}
