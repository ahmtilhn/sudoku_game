from pathlib import Path

root = Path(__file__).resolve().parents[1]

def patch(path: str, old: str, new: str, label: str) -> None:
    target = root / path
    source = target.read_text(encoding='utf-8')
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    target.write_text(source.replace(old, new, 1), encoding='utf-8')

# Pre-match cancellation owns and closes its controller instead of marking it as handed off.
patch(
    'lib/features/duel/pre_match_ready_screen.dart',
    "  bool _handedOff = false;\n  bool _connecting = false;\n",
    "  bool _handedOff = false;\n  bool _allowPop = false;\n  bool _connecting = false;\n",
    'prematch allow-pop field',
)
patch(
    'lib/features/duel/pre_match_ready_screen.dart',
    "    final controller = _controller;\n    if (controller == null) {\n      _handedOff = true;\n      if (mounted) Navigator.of(context).pop();\n      return;\n    }\n",
    "    final controller = _controller;\n    if (controller == null) {\n      setState(() => _allowPop = true);\n      if (mounted) Navigator.of(context).pop();\n      return;\n    }\n",
    'prematch null controller exit',
)
patch(
    'lib/features/duel/pre_match_ready_screen.dart',
    "    if (!mounted) return;\n    _handedOff = true;\n    Navigator.of(context).pop();\n  }\n\n  void _ready()",
    "    await _snapshotSubscription?.cancel();\n    await _connectionSubscription?.cancel();\n    await controller.dispose();\n    _controller = null;\n    _snapshotSubscription = null;\n    _connectionSubscription = null;\n    if (!mounted) return;\n    setState(() => _allowPop = true);\n    Navigator.of(context).pop();\n  }\n\n  void _ready()",
    'prematch dispose before pop',
)
patch(
    'lib/features/duel/pre_match_ready_screen.dart',
    "      canPop: _handedOff,\n",
    "      canPop: _handedOff || _allowPop,\n",
    'prematch pop condition',
)

# A Firebase-ready pass recovers startup ordering races for native leaderboard sync.
patch(
    'lib/main.dart',
    "        if (!push.userDisabled.value) {\n          if (push.permissionGranted.value) {\n            await push.refreshRegistration();\n          } else {\n            await push.requestPermissionAndRegister();\n          }\n        }\n",
    "        if (!push.userDisabled.value) {\n          if (push.permissionGranted.value) {\n            await push.refreshRegistration();\n          } else {\n            await push.requestPermissionAndRegister();\n          }\n        }\n        await PlatformLeaderboardService.instance.syncAuthoritativeRatings();\n",
    'firebase-ready leaderboard sync',
)

# Do not classify a pre-start cancelled lobby as a played recent opponent.
index_path = root / 'backend/social_worker/src/index.ts'
index_source = index_path.read_text(encoding='utf-8')
old_recent = """      this.env.DB.prepare(
        `INSERT INTO recent_opponents (
           player_low_id, player_high_id, last_challenge_id, last_winner_id, last_played_at
         ) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(player_low_id, player_high_id) DO UPDATE SET
           last_challenge_id = excluded.last_challenge_id,
           last_winner_id = excluded.last_winner_id,
           last_played_at = excluded.last_played_at`,
      ).bind(
        ...orderedPair(duel.playerA.player.id, duel.playerB.player.id),
        duel.challengeId,
        winnerId,
        now,
      ),
"""
new_recent = """      ...(duel.startedAt !== null
        ? [
            this.env.DB.prepare(
              `INSERT INTO recent_opponents (
                 player_low_id, player_high_id, last_challenge_id, last_winner_id, last_played_at
               ) VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(player_low_id, player_high_id) DO UPDATE SET
                 last_challenge_id = excluded.last_challenge_id,
                 last_winner_id = excluded.last_winner_id,
                 last_played_at = excluded.last_played_at`,
            ).bind(
              ...orderedPair(duel.playerA.player.id, duel.playerB.player.id),
              duel.challengeId,
              winnerId,
              now,
            ),
          ]
        : []),
"""
if index_source.count(old_recent) != 1:
    raise RuntimeError('recent opponent settlement block not found exactly once')
index_path.write_text(index_source.replace(old_recent, new_recent, 1), encoding='utf-8')

# Clean, readable audit document.
(root / 'docs/CHALLENGE_SYSTEM_AUDIT.md').write_text("""# Challenge System Audit

## Scope

This audit follows challenge creation, notification delivery, exact status polling, acceptance, decline, cancellation, room funding, lobby readiness, reconnect, surrender, settlement, result UI, rematch, Coin, ELO, recent opponents, and platform leaderboard mirroring.

## Product rules

- Direct friend challenges are **friendly** matches. They use the authoritative Sudoku engine and Coin entry/pot economy, but do not change ranked ELO or ranked leaderboards. This prevents rating boosting between friends.
- Normal online matchmaking is **ranked**. Completed ranked matches and ranked forfeits update global and difficulty ELO, backend leaderboards, Google Play Games/Game Center mirrors when configured, and supported platform game-stat events.
- Leaving before a match starts cancels the lobby and refunds both entry fees. Leaving after the match starts is an explicit surrender: the opponent wins and normal settlement runs.

## Hardening delivered

- Exact challenge GET and challenger DELETE endpoints.
- One pending challenge per sender/recipient direction and a reverse-pending guard.
- Active-match and both-player Coin checks before creation and acceptance.
- Race-safe accept/decline updates and single-shot response notifications.
- Accepted rooms are returned only when a live match row and funded escrow both exist.
- Terminal or unfunded room replay is rejected by both WebSocket entry paths.
- A two-minute authoritative lobby timeout prevents abandoned rooms from holding Coin indefinitely.
- Challenge polling verifies `challengeId` before using `activeMatch`.
- The sender sees decline, expiry, and cancellation separately and can cancel a pending challenge.
- Pre-match back cancels on the server, waits for refund settlement, and closes the room connection.
- Active matches expose a visible surrender action. System back uses the same confirmed surrender flow and keeps the socket alive until the server acknowledges the result.
- Result UI waits for settled rating data, reports net Coin result, routes rematch safely, and opens ranked matchmaking for **Find new match**.
- Recent opponents are written only after a match actually starts.
- Native platform leaderboards resync authoritative backend ratings at startup, after Firebase initialization, and when the leaderboard hub connects, recovering missed per-match submissions.

## ELO and leaderboard behavior

- **Friend challenge:** friendly, ELO delta `0`, no ranked leaderboard update.
- **Ranked win/loss/draw:** updates global and selected-difficulty ELO in D1.
- **Ranked surrender:** counts as a normal rated loss/win because the match started.
- **Pre-match cancellation or lobby timeout:** no ELO change and both Coin entries are refunded.
- Google Play Games IDs are configured in the client. Game Center identifiers remain disabled while placeholder IDs are present.

## Remaining deployment and device gates

- Apply D1 migration `0016_challenge_hardening.sql` and deploy the updated Worker.
- Verify Cloudflare FCM secrets and Firebase/APNs configuration.
- Replace iOS Game Center placeholder leaderboard identifiers with the real App Store Connect identifiers.
- Run physical Android-to-Android, iOS-to-iOS, and Android-to-iOS tests for foreground/background/terminated notification delivery, reconnect, surrender, lobby cancellation refund, win/loss/draw, rematch, and ranked ELO propagation.
""", encoding='utf-8')

print('Final challenge hardening cleanup applied.')
