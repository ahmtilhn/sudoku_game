# Online Duel Protocol

Protocol version: `1`.

Client messages use:

```json
{
  "v": 1,
  "type": "move",
  "requestId": "client-generated-id",
  "expectedRevision": 12,
  "payload": {}
}
```

Server messages use:

```json
{
  "v": 1,
  "type": "snapshot",
  "eventId": "room:revision:type",
  "revision": 13,
  "serverTime": 1760000000000,
  "payload": {}
}
```

## Client Messages

- `ready`: marks the authenticated player's seat ready.
- `game_screen_loaded`: marks the authenticated player's game screen rendered
  after the first authoritative snapshot.
- `move`: `{ "cellIndex": 0, "value": 1 }`.
- `forfeit`: forfeits an active match.
- `request_snapshot`: asks for the current public state.
- `ping`: returns `pong`.

The client must not send score, winner, board, rating, result, elapsed time,
solution, or next player as authoritative data. The Durable Object ignores
those concepts and computes them from state.

## Server Events

- `connected`
- `snapshot`
- `player_presence`
- `player_ready`
- `screen_loaded`
- `ready_window_started`
- `ready_window_cancelled`
- `match_started`
- `game_started`
- `move_accepted`
- `move_rejected`
- `turn_changed`
- `turn_timeout`
- `player_forfeited`
- `match_completed`
- `rating_updated`
- `pong`
- `protocol_error`
- `server_error`

## Snapshot

Snapshots include room ID, match ID, mode, difficulty, status, local seat,
public player metadata, public puzzle, current board, scores, mistakes,
correct move counts, timeouts, current turn, turn number, ready deadline, turn
deadline, server time, ready state, presence state, screen loaded state,
revision, winner, finish reason, rating deltas after settlement, and online
coin settlement after completion.

Snapshots never include the solution grid, Firebase UID, FCM token, IP address,
or internal player ID.

## Error Codes

- `invalid_json`
- `invalid_envelope`
- `unsupported_message_type`
- `stale_revision`
- `game_not_active`
- `not_your_turn`
- `invalid_cell`
- `invalid_value`
- `cell_not_editable`
- `cell_already_filled`
- `wrong_value`

If `stale_revision` includes a recovery snapshot, the Flutter controller applies
it. Otherwise it sends `request_snapshot`.

## Close Codes

- `1009`: message larger than 4096 bytes.
- `4001`: same player connected from a newer gameplay socket.
- `4003`: authenticated player is not a room participant.

