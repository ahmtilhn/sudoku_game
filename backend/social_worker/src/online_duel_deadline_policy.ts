import {
  applyDueDeadlines as applyEngineDueDeadlines,
} from './online_duel_engine';
import {
  type DuelState,
  type PublicEvent,
  event,
} from './online_duel_model';

/// Wraps the authoritative deadline engine so the ten-second Ready countdown
/// can finish without starting the playable turn clock before either client has
/// actually reached the Sudoku board.
///
/// The engine still owns every normal timeout/forfeit/match-duration rule. The
/// only intercepted transition is ready_window -> active. At that boundary we
/// keep `status = active` so existing clients navigate to the game screen, but
/// clear the gameplay clock and reset the screen-loaded handshake. The clock is
/// armed later by `applyScreenLoaded` once both board clients report ready.
export function applyDueDeadlines(
  state: DuelState,
  now: number,
): PublicEvent[] {
  const readyWindowExpired =
    state.status === 'ready_window' &&
    state.readyDeadline !== null &&
    now >= state.readyDeadline;

  const events = applyEngineDueDeadlines(state, now);

  if (
    !readyWindowExpired ||
    state.status !== 'active' ||
    state.startedAt === null
  ) {
    return events;
  }

  state.startedAt = null;
  state.turnStartedAt = null;
  state.turnDeadline = null;
  state.playerA.screenLoaded = false;
  state.playerB.screenLoaded = false;
  state.revision++;

  // GameRoom personalizes snapshot events per socket, so both clients receive
  // the same active-but-not-yet-timed board-loading state.
  return [event(state, 'snapshot', now, {})];
}
