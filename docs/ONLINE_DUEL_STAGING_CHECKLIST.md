# Online Duel Staging Checklist

Decision target: `READY FOR TWO-DEVICE STAGING TEST`.

## Local Code Gate

- `npm run typecheck`
- `npm test`
- `npm run puzzles:verify`
- `npm run db:local`
- `python tool/validate_localizations.py`
- `python tool/validate_translation_quality.py`
- `flutter analyze`
- `flutter test --concurrency=1 --timeout 120s -r expanded`
- `flutter build apk --debug`

## Debug Backend Selection

A plain debug `flutter run` now falls back to the checked staging Worker URL when
`SOCIAL_BACKEND_URL` is not supplied. Android and iOS therefore use the same
REST/WSS host during local device testing.

Release and profile builds do not use that fallback. They must still be built
with an explicit HTTPS value:

```powershell
flutter run --release `
  --dart-define=SOCIAL_BACKEND_URL=https://YOUR-STAGING-WORKER.example
```

## Staging Preflight

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\online_duel_staging_preflight.ps1 `
  -BackendUrl "https://YOUR-STAGING-WORKER.example"
```

The script reports placeholders, checks `/health` and `/version`, runs local
backend/Flutter tests, verifies puzzle bank and translations, and lists required
secret names without printing secret values.

## Remote Database Gate

Apply every pending migration, including
`0004_ranked_queue_cleanup.sql`. Migration 0004 removes already matched queue
rows and prunes abandoned queue tickets so later searches cannot select a ghost
or already-busy opponent.

## Staging Build

Run only with a real HTTPS staging Worker URL:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\build_online_staging.ps1 `
  -BackendUrl "https://YOUR-STAGING-WORKER.example"
```

The script rejects missing, local, placeholder, query, username, password, or
token-bearing URLs.

## Two-Token Smoke

Set environment variables without logging values:

- `SOCIAL_BACKEND_URL`
- `PLAYER_A_ID_TOKEN`
- `PLAYER_B_ID_TOKEN`
- optional `PLAYER_A_APP_CHECK_TOKEN`
- optional `PLAYER_B_APP_CHECK_TOKEN`

Run:

```powershell
cd backend/social_worker
npm run smoke:two-player
npm run smoke:ranked
```

## Cross-Platform Device Gate

Use two different Firebase accounts and the same difficulty on:

1. Android + Android
2. Android + iOS

For each pair verify queue start, match discovery, WebSocket room connection,
ready state, correct and wrong moves, per-player notifications, turn ownership,
reconnect, forfeit, result, rating and history.

## Production Gate

Production remains blocked until physical Android and iOS devices complete
challenge and ranked flows through the deployed staging Worker, App Check
metrics are validated, abuse tests pass, and Data Safety/privacy policy updates
are done.
