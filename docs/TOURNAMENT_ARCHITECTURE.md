# Tournament Architecture

This document defines the tournament design lock for future phases. Phase 0 does not create tournament tables, UI or runtime routes.

## Scope Boundaries

- Tournaments are closed-loop, in-game competitive events only.
- Rewards may be in-game Coins, cosmetics or rating/title metadata only after explicit policy review.
- No cash, physical prizes, gift cards, crypto, transferable value, withdrawals or real-world-value rewards.
- No chat system and no replay UI are part of tournament work.
- The server validates attempts, scoring, eligibility, rewards and country contribution.

## Tournament Lifecycle

| State | Meaning | Allowed next states |
|---|---|---|
| `draft` | Admin-created but invisible to players. | `scheduled`, `cancelled` |
| `scheduled` | Visible countdown; no registration yet unless configured. | `registration`, `cancelled` |
| `registration` | Players may register/reserve eligibility. | `live`, `locked`, `cancelled` |
| `live` | Attempts may be started and submitted. | `locked`, `cancelled` |
| `locked` | No new attempts; late submissions may still settle. | `settling`, `cancelled` |
| `settling` | Server validates results and computes standings/rewards. | `settled`, `cancelled` |
| `settled` | Final standings and server-issued rewards are immutable. | `archived` |
| `archived` | Read-only historical event. | none |
| `cancelled` | Event is void; eligible refunds are server-issued idempotently. | `archived` |

## Attempt Lifecycle

| State | Meaning | Server responsibility |
|---|---|---|
| `reserved` | Attempt slot reserved before puzzle/session starts. | Reserve once per player/event according to rules. |
| `started` | Puzzle/session issued by server. | Record server start time and puzzle fingerprint. |
| `completed` | Client indicates completion. | Treat as advisory until validation. |
| `submitted` | Submission received. | Persist bounded audit data and begin validation. |
| `validated` | Server accepted result. | Update leaderboard/country score idempotently. |
| `disqualified` | Server rejected attempt. | Store reason code; do not grant rewards. |
| `abandoned` | Attempt expired or was left incomplete. | Close without score/reward, apply policy-defined fee/refund. |

## Server-Authoritative Scoring

The client may send move timing and completion payloads, but the Worker must validate:

- player eligibility and registration;
- tournament status and server time window;
- attempt ownership and single-use attempt id;
- puzzle fingerprint and issued puzzle id;
- move legality or final board validity depending on tournament type;
- elapsed time bounded by server timestamps;
- mistake/forfeit/timeout policy;
- idempotency key and duplicate submission behavior.

The client must never provide final authoritative score, country score, rating delta, reward amount or rank.

## Tournament Table Plan

Future migration `0019_tournaments_core.sql` should introduce:

- `competitive_tournaments`: id, slug, status, type, scope, starts/ends/locks, rules json, feature flag, created/updated audit fields.
- `tournament_registrations`: tournament id, player id, status, registered at, eligibility snapshot, idempotency key.
- `tournament_attempts`: tournament id, player id, attempt id, status, puzzle assignment, server timestamps, validation digest.
- `tournament_attempt_audit`: bounded security events and payload digests, not replay archive data.

Future migration `0020_tournament_results_and_country_scores.sql` should introduce:

- `tournament_results`: immutable validated result rows, rank inputs, tie-break fields, disqualification reason.
- `tournament_rewards`: idempotent server-issued in-game rewards.
- `country_competition_scores`: aggregate country points per tournament/season.

## API Draft

| Endpoint | Notes |
|---|---|
| `GET /v1/tournaments` | Lists visible events; hidden draft events require admin route later. |
| `GET /v1/tournaments/:id` | Returns status, rules, server time, registration and attempt state. |
| `POST /v1/tournaments/:id/register` | Server checks eligibility and creates one registration idempotently. |
| `POST /v1/tournaments/:id/start-attempt` | Server assigns puzzle/session and attempt id. |
| `POST /v1/tournaments/:id/submit` | Server validates and stores result; duplicate submit returns previous result. |
| `GET /v1/tournaments/:id/leaderboard` | Server-computed rank list. |
| `GET /v1/tournaments/:id/countries` | Server-computed country standings. |

## Operational Requirements

- Add a top-level Worker `scheduled()` handler before cron-driven status transitions.
- Keep Durable Object alarms for live duel room deadlines; do not reuse them for global event settlement.
- All status transitions must be idempotent and safe to retry.
- Admin/event configuration must be protected by a separate admin auth model before any write route is exposed.
