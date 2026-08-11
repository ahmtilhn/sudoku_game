# Integrity and App Check Setup

## Scope

Integrity checks protect high-value online actions. They must not block offline Sudoku. Enforcement starts in metrics mode, then moves behind feature flags after false-positive review.

## Firebase App Check

1. Register Android and iOS apps in Firebase.
2. Android provider: Play Integrity.
3. iOS provider: App Attest where available, DeviceCheck fallback where needed.
4. Flutter provider setup must use production providers for release builds.
5. Debug tokens must stay local and must not be committed.
6. Start with monitoring and metrics.
7. Enable backend enforcement only after telemetry is stable.

## High-value Android requests

Use Play Integrity Standard requests for:

- `tournament_start`
- `tournament_submit`
- `purchase_verification`
- `rewarded_reward`

Rules:

- Compute `requestHash` from the canonical request body and important server-known fields.
- Bind the integrity token to `requestHash`.
- Decode and verify the token on the backend.
- Reject hash mismatches when enforcement is enabled.
- Track token hashes to prevent replay.
- Log false-positive telemetry without logging raw tokens.

## High-value iOS requests

Use App Attest for supported devices:

1. Register an App Attest key.
2. Issue a one-time backend challenge.
3. Bind the assertion to `clientDataHash`.
4. Consume the challenge once.
5. Store attestation state by Firebase UID and key ID hash.
6. For unsupported devices, use a risk-based fallback rather than blocking offline play.

## Failure policy

- Offline Sudoku remains available.
- Ranked and tournament flows show a clear integrity error when enforcement blocks them.
- First rollout uses `integrityEnforcement=false` metrics mode.
- Failed attestation creates telemetry and optional manual review state.
- Do not apply hard bans on day one.

## Data model

- `platform_identity_links`: verified platform identity mapping, hashed platform player IDs.
- `platform_identity_challenges`: one-time Game Center, Google, and App Attest challenges.
- `high_value_attestations`: request hash, token hash, verdict, and risk state.
- `platform_friend_relations`: user-consented platform social imports.
- `platform_leaderboard_mirror_queue`: backend-approved mirror writes with retry state.

## Manual validation

- App Check missing is monitored when enforcement is off and blocked only when on.
- Play Integrity `requestHash` mismatch blocks high-value online actions.
- Unsupported App Attest creates manual-review risk state but keeps offline play available.
- Token replay is rejected.
- No secret, private key, service account JSON, or debug token is stored in the repository.
