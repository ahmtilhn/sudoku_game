# Remote Branch Audit

Generated from all remote refs against the current `main` branch. A positive `unique patches` count means Git history differs; it does **not** automatically mean a missing product behavior. Stale branches were never merged wholesale. Each was classified by changed files and by whether the current main already contains a newer implementation.

## Result

- Remote branches audited: **45**
- Branches with no unique patch relative to main: **25**
- Diverged branches with unique historical patches: **20**
- Known requested behavior missing from main after selective comparison: **none**
- Whole stale branches merged: **none**
- Development target: **main only**

## Detailed table

| Branch | Ahead | Behind | Unique patches | Decision | Reason |
|---|---:|---:|---:|---|---|
| `agent-fix-play-games-annotated-data` | 0 | 468 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent-integrate-codex-firebase` | 0 | 430 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent-mobile-friend-join-backend-hardening` | 0 | 440 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent-nonblocking-startup` | 2 | 374 | 2 | Superseded | Non-blocking optional startup is already implemented in current `main.dart`. |
| `agent-optimize-mobile-ci` | 0 | 361 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent-restore-custom-gameplay` | 0 | 530 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/android-release-services-hardening` | 0 | 103 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/challenge-system-hardening` | 36 | 413 | 36 | Superseded | Current challenge invitation/waiting/social flows and safe-error handling are newer; wholesale merge would reintroduce old code. |
| `agent/complete-ux-overhaul` | 64 | 605 | 52 | Ported selectively | Requested gameplay, profile, feedback, 16×16 and error-safety work was reimplemented directly on current main. |
| `agent/complete-ux-overhaul-ci` | 15 | 614 | 15 | Superseded | Current main has stricter localization, safe-message, UX-contract, fatal-analyze, test, debug and release gates. |
| `agent/finalize-challenge-system` | 0 | 351 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/fix-android-continue-resource` | 4 | 566 | 4 | Superseded | Current localization resources are validated by `tool/validate_localizations.py` and release CI. |
| `agent/fix-localization-placeholders` | 1 | 572 | 1 | Superseded | Current localization catalog and validation include the later placeholder handling. |
| `agent/fix-preferences-api` | 2 | 551 | 2 | Superseded | Current session storage uses SharedPreferencesAsync and now has deterministic in-memory test support. |
| `agent/fix-test-hang-and-warning` | 2 | 568 | 2 | Superseded | Current CI has explicit test timeouts and the complete test suite passes. |
| `agent/fix-test-regressions` | 0 | 538 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/google-play-games-production-fix` | 0 | 346 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/merge-dedup-fix` | 0 | 438 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/online-main-sync` | 0 | 463 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/pin-number-pad-bottom` | 3 | 573 | 3 | Ported selectively | Current gameplay uses `NumberPadDock` and a responsive 16-value grid. |
| `agent/platform-auth-backend` | 0 | 436 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/platform-localization` | 29 | 506 | 29 | Superseded | Current platform screens use the unified localization catalog and user-safe messages. |
| `agent/playable-offline-prototype` | 33 | 609 | 33 | Superseded | Current app is later and includes persisted offline 16×16 Fantasy gameplay. |
| `agent/portrait-only-responsive` | 3 | 539 | 3 | Intentionally not merged | A forced portrait policy was not requested; current responsive layouts retain broader device support. |
| `agent/random-career-and-matchmaking` | 16 | 567 | 14 | Superseded | Current career and matchmaking implementations are newer and include safe-state/error handling. |
| `agent/release-preflight-fix` | 0 | 354 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/repair-conflicted-main` | 12 | 440 | 12 | Obsolete | Historical conflict-repair branch; current main contains later resolved implementations. |
| `agent/setup-platform-credentials` | 0 | 435 | 0 | Already represented | No unique patch remains relative to current main. |
| `agent/stabilize-build-tests` | 0 | 535 | 0 | Already represented | No unique patch remains relative to current main. |
| `codex/complete-career-ui-flow` | 7 | 608 | 7 | Superseded | Current career hub/flow and result handling are later implementations. |
| `codex/complete-ui-gaps` | 17 | 583 | 13 | Ported selectively | Relevant UI gaps were covered by the current main UX overhaul; branch is far behind. |
| `codex/complete-ui-gaps-v2` | 14 | 580 | 10 | Ported selectively | Relevant UI gaps were covered by the current main UX overhaul; branch is far behind. |
| `codex/firebase-google-production-setup` | 1 | 481 | 1 | Superseded | Current release/Firebase/Play Games validation and AAB inspection are stricter. |
| `fix/challenge-decline-waiting-state` | 2 | 374 | 2 | Superseded | Current challenge waiting/invitation state handling is newer and user-safe. |
| `fix/exact-challenge-waiting-status` | 3 | 418 | 3 | Superseded | Current challenge status flow is newer and covered by current UX/service code. |
| `fix/duel-finish-error` | 0 | 558 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/duel-finish-error-3b51` | 0 | 561 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/ios-platform-preflight` | 0 | 407 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/multiplayer-balance-resync` | 0 | 532 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/multiplayer-economy` | 0 | 530 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/multiplayer-error-handling` | 0 | 562 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/multiplayer-issues` | 0 | 513 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/multiplayer-issues-v2` | 0 | 517 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/multiplayer-race-conditions` | 0 | 524 | 0 | Already represented | No unique patch remains relative to current main. |
| `fix/social-backend-deployment` | 0 | 420 | 0 | Already represented | No unique patch remains relative to current main. |

## Merge rule used

1. Never merge a branch only because it is ahead by commit count.
2. Compare changed files and product behavior against the latest main.
3. Port only missing behavior onto main.
4. Keep intentionally excluded platform policies—such as forced portrait mode—out of main unless explicitly requested.
5. Validate every port with localization checks, user-safe-message checks, UX contracts, fatal analyzer, tests, debug build and release build.
