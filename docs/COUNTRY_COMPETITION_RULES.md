# Country Competition Rules

Country competition is a future feature behind `countryTournaments`. This document locks policy and server-authoritative boundaries before implementation.

## Scope

- Country competition is an aggregate in-game leaderboard.
- It must not offer cash, physical prizes, gift cards, transferable value or real-world rewards.
- It must not add chat, clans or social messaging.
- It must not trust client-submitted country scores.

## Country Profile

`/v1/countries/profile` is the future profile endpoint.

Proposed fields:

| Field | Meaning |
|---|---|
| `countryCode` | ISO 3166-1 alpha-2 country selected or verified by policy. |
| `source` | `self_selected`, `storefront`, `platform`, `admin_adjusted`. |
| `lockedUntil` | Prevents frequent country switching during active seasons/events. |
| `updatedAt` | Last profile update timestamp. |
| `seasonId` | Optional current season lock context. |

## Selection Policy

- Default for early phases should be self-selected country with a clear lock period.
- Do not infer or expose precise location.
- Storefront/platform country may be used only as a coarse eligibility signal if policy permits.
- Country changes during a live tournament must not affect already submitted attempts.
- Country choice must be private except where shown as an aggregate leaderboard entry.

## Scoring Rules

The Worker computes country points from validated tournament results only.

Recommended initial scoring:

- Each validated player result contributes to their locked country for that tournament.
- Country standings use normalized points to avoid pure population advantage.
- Disqualified, abandoned or invalid attempts contribute zero.
- Duplicate submissions and retries must be idempotent.
- Country aggregate rows are derived from immutable validated result rows.

The client must never send country points, country rank, reward amount or validated tournament result.

## Country Competition Tables

Future migration `0020_tournament_results_and_country_scores.sql` should include:

- `player_country_profiles`: player id, country code, source, locked until, season/tournament lock context.
- `country_competition_scores`: tournament/season id, country code, points, participant count, validated result count, updated at.
- `country_score_events`: bounded idempotent audit rows for score contributions.

## API Draft

| Endpoint | Method | Behavior |
|---|---|---|
| `/v1/countries/profile` | GET | Returns current player country profile and lock state. |
| `/v1/countries/profile` | PUT | Sets country only when lock policy allows. |
| `/v1/tournaments/:id/countries` | GET | Returns server-computed country standings. |

## Integrity and Abuse Controls

- Require Firebase Auth for all country profile writes.
- Require App Check according to `integrityEnforcement` before production country events.
- Rate-limit country profile changes.
- Lock country during registration/live tournament windows.
- Keep country score recomputation idempotent and replay-safe.

## Phase 0 Decision

No country competition runtime is implemented in this phase. The next compatible migration number for country support is `0020`, after feature flags, avatar/platform identity and tournament core tables are introduced.
