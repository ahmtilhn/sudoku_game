# Online Duel Test Plan

## Local Automated Tests

- `npm run typecheck`
- `npm test`
- `npm run db:local`
- `python tool/validate_localizations.py`
- `flutter analyze`
- `flutter test --concurrency=1 --timeout 90s -r expanded`
- `flutter build apk --debug`
- `flutter build appbundle --release`

## Staging Tests Required

1. Deploy the Worker to staging.
2. Apply D1 migrations remotely.
3. Set Firebase/FCM secrets through Wrangler.
4. Build the app with staging `SOCIAL_BACKEND_URL`.
5. Use two Firebase-authenticated test accounts on two devices.
6. Verify challenge accept, WebSocket connect, ready, correct move, wrong move,
   duplicate request, stale revision, reconnect, explicit forfeit, settlement,
   history, ratings, and leaderboards.

## Abuse Tests

- Third account room connection returns 403.
- Out-of-turn moves are rejected.
- Duplicate `requestId` does not change score twice.
- Invalid cell and value are rejected.
- Old revision returns `stale_revision`.
- Reconnect grace does not reset forever.

