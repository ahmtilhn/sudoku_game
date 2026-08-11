# Challenge System Audit

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
