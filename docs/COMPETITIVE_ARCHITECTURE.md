# Competitive Architecture

This document defines the production safety boundaries for Sudoku Duel competitive systems.

The current release has two intentionally separate competitive layers:

- **authoritative online duel + hidden Elo/MMR**: existing matchmaking, GameRoom, result and rating authority;
- **visible RP + player identity**: additive progression, Bronze III through Master I, rank rewards, frames, avatars, titles and achievement decorations.

For exact RP numbers and reward tables, see `docs/RANKED_RATING_SYSTEM.md`.

## Current Capability Matrix

| Area | Status | Primary storage / route | Boundary |
|---|---|---|---|
| Ranked matchmaking | Present | `ranked_queue`, `/v1/matchmaking/queue` | Existing hidden rating/difficulty pairing remains authoritative. |
| Hidden Elo/MMR settlement | Present | `player_ratings`, `match_players.rating_*`, `GameRoom` settlement | Server-owned skill estimate. Normal player-facing competitive UI must not treat this as visible rank. |
| Visible Rank Points | Present | `player_rank_progression`, `rank_progression_settlements` | Derived only from already-authoritative rated match rows. Starts at 0 RP. |
| Visible rank ladder | Present | Bronze III -> Master I | 15 divisions; normal divisions are 300 RP. |
| Rank rewards | Present | `rank_reward_grants`, `coin_ledger` | Lifetime first-time only, database-idempotent; total path reward 12,000 Coin. |
| RP leaderboard | Present | `/v1/competitive/rank-leaderboard` | Main in-app competitive ladder. Hidden MMR is not returned. |
| Public RP profile | Present | `/v1/competitive/rank-player/:publicId` | Privacy-aware public rank/RP/stats/composite identity; hidden MMR is not returned. |
| Profile identity | Present | `players.avatar_key`, `player_rank_progression` | Composite avatar + unlocked/equipped frame + up to three achievement decorations. |
| Avatar presets | Present | Flutter `AvatarPresetCatalog` | 96 game-relevant local presets, no remote stock-image dependency. |
| Rank frames | Present | 15 RP division frames | Permanently unlocked once reached; equipped frame is cosmetic and does not redefine current rank. |
| Achievement decorations | Present | `achievement_cosmetics`, `achievement_showcase` | Up to three equipped frame decorations. |
| Rank titles | Present | rank progression profile | Master / Master I currently supported. |
| Friends | Present | `friendships`, friend request/respond routes | Friend graph remains independent from platform friends. |
| Challenges | Present | `challenges`, `rematch_invitations` | Friendly challenge reuse of duel protocol does not automatically grant RP. |
| Coin economy | Present | `players.online_coins`, `coin_ledger`, match escrow | Existing wallet / escrow / payout authority remains independent from RP computation. |
| Seasons | Not active | future | Do not retrofit season rules into hidden Elo or lifetime RP without a versioned design. |
| Tournaments | Not active | future | Must remain feature-gated and server-authoritative. |
| Country competition | Not active | future | Must use separate server-owned aggregates. |

## Non-Negotiable Online Authority Boundary

The RP/identity work must **not** replace, fork or become a prerequisite for any of these systems:

- GameRoom / Durable Object match authority
- WebSocket duel protocol
- move validation
- Sudoku puzzle state
- timeout authority
- disconnect / forfeit authority
- winner determination
- matchmaking queue behavior
- hidden Elo/MMR settlement
- Coin entry escrow
- match payout / refund
- rematch and challenge room creation

The online match must remain capable of finishing correctly even if RP/profile reconciliation is temporarily unavailable.

## Server Authority Rules

The Worker owns:

- Coin balances and ledger rows;
- match escrow, payout and refund;
- online duel score, winner and finish reason;
- hidden Elo/MMR deltas;
- visible RP settlement;
- rank reward grants;
- rank/frame/title unlock eligibility;
- achievement unlocks;
- public composite identity key.

The Flutter client may request actions and render returned state. It must never authoritatively send:

- winner or match result;
- hidden MMR;
- RP delta or resulting RP;
- rank tier;
- Coin reward amount;
- unlocked frame/title/achievement state;
- tournament or country score.

## Competitive Data Ownership

| Data | Owner | Storage | Notes |
|---|---|---|---|
| Account identity | Firebase Auth + Worker | `players.firebase_uid` | Firebase UID remains account key. |
| Public identity | Worker | `players.public_id`, `username`, `display_name` | Public ID is permanent Friend ID. |
| Hidden skill | Worker | `player_ratings`, `match_players.rating_*` | Starts at 1000; used for matchmaking and RP opponent-strength snapshots. |
| Visible progression | Worker | `player_rank_progression` | Starts at 0 RP. |
| RP audit | Worker | `rank_progression_settlements` | Idempotent per match/player. |
| Lifetime rank rewards | Worker | `rank_reward_grants` | `(player_id, rank_key)` uniqueness prevents repeat grants. |
| Wallet | Worker | `players.online_coins`, `coin_ledger` | Every mutation requires idempotency. |
| Match result | Worker Durable Object + D1 | `matches`, `match_players`, settlement tables | Client payload is not result authority. |
| Equipped avatar/frame/title | Worker | `player_rank_progression` + composite `players.avatar_key` | Selection is validated server-side. |
| Equipped achievement badges | Worker | `achievement_showcase` | Maximum three. |
| Friends/challenges | Worker | `friendships`, `challenges`, `rematch_invitations` | Existing social flow remains independent of rank math. |
| Push tokens | Worker + Firebase Messaging | `device_tokens` | Device-scoped. |

## RP Reconciliation Boundary

Visible rank settlement is intentionally post-authority:

```text
GameRoom / match authority
        |
        v
existing match + hidden-MMR settlement
        |
        v
rank progression reconciliation
        |
        +--> RP audit row
        +--> lifetime rank reward grant
        +--> achievement unlock reconciliation
        +--> composite frame/avatar refresh
        |
        v
player-facing result/profile/leaderboard UI
```

`rank_post_settlement.ts` may update only rank-derived state and public identity. It must not mutate match authority, matchmaking, Elo tables or escrow.

## Player Identity Contract

The public player identity is composed of:

1. avatar base;
2. equipped rank frame;
3. zero to three equipped achievement decoration keys.

The encoded server key uses versioned composition:

```text
idv1|<avatar>|<frame>|<decoration1,decoration2,decoration3>
```

### Avatar privacy rule

Built-in avatar presets may be shown to other players.

Native Game Center / Google Play Games image bytes/URLs are owner-local presentation data unless a future explicit backend sync/consent system is implemented. A remote player's platform-style key must never resolve using the viewer's own native platform avatar.

### Cosmetic versus competitive truth

A previously unlocked frame can remain equipped after the player drops to a lower current rank.

Therefore UI must keep these concepts separate:

- current rank = derived from current RP;
- season/lifetime peak = historical competitive data;
- equipped frame = cosmetic selection from unlocked frames.

A cosmetic frame alone is never evidence of current rank.

## Achievement Decoration Rules

Achievement decorations are optional attachments to the frame.

Current supported ranked examples include:

- undefeated 10 / 25 / 50;
- win streak 5 / 10 / 25;
- reach Silver / Gold / Platinum / Master / Master I;
- Giant Slayer;
- ranked veteran 100 / 500 / 1000;
- perfect ranked win / perfect ten.

Only unlocked achievements that have a registered cosmetic decoration can be equipped. The backend enforces the three-slot limit.

## Rank Reward Safety

Rank Coin rewards are lifetime-first-time only.

Database boundary:

```text
PRIMARY KEY(player_id, rank_key)
```

Ledger boundary:

```text
rank_reward:<playerId>:<rankKey>
```

A profile refresh, result-screen retry, network retry, demotion or later re-promotion must not duplicate a reward.

## Player-Facing Ranking Rule

Normal Sudoku Duel competitive UI should display:

- visible rank tier;
- visible RP;
- RP progress to next division;
- RP result delta;
- rank-up / reward events.

Hidden Elo/MMR remains available internally for matchmaking and compatibility tooling. It is not the primary in-app competitive rank.

Native/platform leaderboard integrations may remain isolated compatibility surfaces, but they do not define the Sudoku Duel in-app rank.

## Friendly Challenge Rule

Friendly challenges remain unranked by default.

Reusing the online duel room, score or timeout system for a friendly challenge does not make it RP-rated. A future rated-challenge product would require an explicit server-side mode and separate product decision.

## Future Seasons / Tournaments

Future systems must be additive and versioned. They must not silently overload lifetime RP or hidden MMR.

Before enabling seasons or tournaments, define explicitly:

- season start/end and eligibility;
- placement behavior;
- season RP reset/soft-reset policy;
- lifetime peak versus season peak;
- season-end rewards;
- tournament eligibility and anti-abuse rules;
- whether tournament matches are separately rated;
- migration/backfill behavior.

## Production Change Rule

When modifying competitive code:

1. preserve existing online result authority;
2. prefer additive derived tables/routes;
3. make every reward/settlement idempotent;
4. keep hidden MMR out of normal visible rank UI;
5. test retries and duplicate requests;
6. test 9x9 and 16x16 through the same architecture;
7. do not add Samurai Sudoku as part of competitive work;
8. do not use client-supplied rank/reward values as authority.
