# Gameplay UX Spec

## Active Online Duel

The active duel hierarchy is:

1. Compact gameplay app bar.
2. Player header with local player, one timer, and opponent.
3. Score balance indicator.
4. Sudoku board.
5. Number pad.
6. Context actions and inline status.

There must be no large turn banner during active play. Text such as "Your turn", "Opponent's turn", and "Move time" must not appear as a separate upper banner. The visible timer is owned by the header and ELO is reserved for lobby, profile, leaderboard, and result surfaces.

## Turn State

- The active player plate uses border, ring, and status badge changes.
- Opponent turn disables input but does not dim, grayscale, or reduce board readability.
- Pending moves disable duplicate number input and show compact inline progress.
- Connection issues use compact status copy and preserve board state.

## Ready State

Ready and connecting use a compact panel with both players, opponent status, one countdown, and one primary ready button. When the match starts, the panel is removed from the active gameplay layout.

## Board

- Outer radius is 16 with a tonal background and subtle border.
- Normal grid lines are low contrast.
- 3x3 boundaries are visible without harsh weight.
- State is communicated by fill, border, icon, font weight, and text color.
- Errors are short feedback states, not permanent red cells.

## Number Pad

- Number targets use at least 48 by 48 logical pixels.
- Small widths use wrapping instead of shrinking below target size.
- Buttons remain readable when disabled.
- Safe area and gesture navigation space are protected.

## Result

The result surface shows win/loss/draw, winner avatar, final score, ELO delta when ranked data exists, Coin outcome, stats backed by server data, and actions. Replay is intentionally absent.
