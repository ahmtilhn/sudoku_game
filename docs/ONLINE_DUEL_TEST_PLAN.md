# Online Duel Test Plan

## Local Automated Tests

- `npm run typecheck`
- `npm test`
- `npm run puzzles:verify`
- `npm run db:local`
- `npm run smoke:two-player` with real staging tokens
- `npm run smoke:ranked` with real staging tokens
- `python tool/validate_localizations.py`
- `python tool/validate_translation_quality.py`
- `flutter analyze`
- `flutter test --concurrency=1 --timeout 120s -r expanded`
- `flutter build apk --debug`
- `tool/build_online_staging.ps1 -BackendUrl "https://REAL-STAGING-WORKER"`

The latest branch adds automated coverage for the debug social-backend fallback,
WSS URL generation, local/opponent feedback separation and personalized recovery
snapshots.

## Staging Tests Required

1. Deploy the Worker to staging.
2. Apply every D1 migration remotely, including
   `0004_ranked_queue_cleanup.sql`.
3. Set Firebase/FCM secrets through Wrangler.
4. Confirm `/health` and `/version` on the deployed Worker.
5. For a plain debug `flutter run`, confirm both devices resolve the same staging
   REST/WSS host. For release/profile builds, pass `SOCIAL_BACKEND_URL`
   explicitly.
6. Use two different Firebase-authenticated accounts and select the same
   difficulty.
7. Verify Android + Android ranked matching.
8. Verify Android + iOS ranked matching.
9. Verify challenge accept, WebSocket connect, ready, correct move, wrong move,
   duplicate request, stale revision, reconnect, explicit forfeit, settlement,
   history, ratings and leaderboards.
10. Confirm a wrong move only shows the local error message while the opponent
    still receives the updated score/turn snapshot.
11. Leave a search running for more than 45 seconds and confirm the queue refresh
    keeps the ticket active without duplicate rooms.
12. Close one searching app, wait beyond the stale-ticket window, and confirm a
    later user is not paired with that ghost ticket.
13. Run `npm run smoke:two-player`.
14. Run `npm run smoke:ranked`.
15. Run `tool/verify_online_aab.ps1` on the staging AAB.

## Abuse and Recovery Tests

- Third account room connection returns 403.
- Out-of-turn moves are rejected.
- Duplicate `requestId` does not change score twice.
- Invalid cell and value are rejected.
- Old revision returns `stale_revision`.
- Reconnect grace does not reset forever.
- Already matched queue rows cannot be selected again.
- Abandoned queue rows are pruned.
- REST and WebSocket waits end with a visible timeout error instead of an
  infinite spinner.
