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
- `flutter test --concurrency=1 --timeout 90s -r expanded`
- `flutter build apk --debug`
- `tool/build_online_staging.ps1 -BackendUrl "https://REAL-STAGING-WORKER"`

Current local results:

- Backend tests: 31 passed.
- Flutter tests: 24 passed.
- Puzzle bank: 100 backend-only ranked puzzles verified.
- Translation quality: 22 online keys verified across supported locales.
- Staging build script: passed with `https://example.invalid` as script
  validation only, not as a real staging AAB.

## Staging Tests Required

1. Deploy the Worker to staging.
2. Apply D1 migrations remotely.
3. Set Firebase/FCM secrets through Wrangler.
4. Build the app with staging `SOCIAL_BACKEND_URL`.
5. Use two Firebase-authenticated test accounts on two devices.
6. Verify challenge accept, WebSocket connect, ready, correct move, wrong move,
   duplicate request, stale revision, reconnect, explicit forfeit, settlement,
   history, ratings, and leaderboards.
7. Run `npm run smoke:two-player`.
8. Run `npm run smoke:ranked`.
9. Run `tool/verify_online_aab.ps1` on the staging AAB.

## Abuse Tests

- Third account room connection returns 403.
- Out-of-turn moves are rejected.
- Duplicate `requestId` does not change score twice.
- Invalid cell and value are rejected.
- Old revision returns `stale_revision`.
- Reconnect grace does not reset forever.

