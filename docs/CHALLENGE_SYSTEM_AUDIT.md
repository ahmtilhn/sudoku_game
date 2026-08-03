# Challenge System Audit

"
    "## Scope
"
    "This audit follows challenge creation, notification delivery, exact status polling, acceptance, decline, cancellation, room funding, lobby readiness, reconnect, surrender, settlement, result UI, rematch, Coin, ELO, recent opponents, and platform leaderboard mirroring.

"
    "## Product rules
"
    "- Direct friend challenges are **friendly** matches. They use the same authoritative Sudoku engine and Coin entry/pot economy, but they do not change ranked ELO or ranked leaderboards. This prevents rating boosting between friends.
"
    "- Normal online matchmaking is **ranked**. Completed ranked matches and ranked forfeits update global and difficulty ELO, backend leaderboards, Google Play Games/Game Center mirrors when configured, and Android Play Games game-stat events.
"
    "- Leaving before a match starts cancels the lobby and refunds both entry fees. Leaving after the match starts is an explicit surrender: the opponent wins and normal settlement runs.

"
    "## Hardening delivered
"
    "- Exact challenge GET and challenger DELETE endpoints.
"
    "- One pending challenge per sender/recipient direction and reverse-pending guard.
"
    "- Active-match and both-player Coin checks before creation and acceptance.
"
    "- Race-safe accept/decline updates and single-shot response notifications.
"
    "- Accepted rooms are returned only when a live match row and funded escrow both exist.
"
    "- Terminal/unfunded room replay is rejected by both websocket entry paths.
"
    "- Two-minute authoritative lobby timeout prevents abandoned rooms from holding Coin indefinitely.
"
    "- Challenge polling verifies challengeId before using activeMatch.
"
    "- Sender sees decline/expiry/cancellation separately and can cancel a pending challenge.
"
    "- Pre-match back cancels on the server and waits for refund settlement.
"
    "- Active matches expose a visible surrender action; system back uses the same confirmed surrender flow and does not dispose the socket before the server acknowledges the result.
"
    "- Result UI waits for settled rating data, reports net Coin result, routes rematch safely, and opens ranked matchmaking for Find new match.
"
    "- Recent opponents are written during authoritative settlement.
"
    "- Native platform leaderboards resync authoritative backend ratings at startup and when the leaderboard hub connects, recovering a missed per-match submission.

"
    "## Remaining deployment and device gates
"
    "- Apply D1 migration `0016_challenge_hardening.sql` and deploy the updated Worker.
"
    "- Verify Cloudflare FCM secrets and Firebase/APNs configuration.
"
    "- Android leaderboard IDs are configured in code; iOS Game Center IDs remain placeholders until real App Store Connect leaderboard identifiers are supplied.
"
    "- Run physical Android↔Android, iOS↔iOS, and Android↔iOS tests for foreground/background/terminated notification delivery, reconnect, surrender, lobby cancellation refund, win/loss/draw, rematch, and ranked ELO propagation.
"
    