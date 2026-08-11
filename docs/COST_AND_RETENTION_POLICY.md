# Cost and Retention Policy

## Scope

This policy covers online duel, matchmaking, D1, Durable Objects, Coin, wallet, rating, friends, challenges, rematches, notifications, platform mirror queues, and transient audit data. It does not add tournament, country tournament, season, clan, chat, or replay features.

## Baseline Route Inventory

| Route | Main queries | Expected count | Rows read/write expectation | Index expectation | Retention |
| --- | --- | ---: | --- | --- | --- |
| `/v1/me` | Firebase UID player lookup, optional profile create/update, wallet snapshot wrapper | 2-5 | 1 player row, 1 wallet row | `players.firebase_uid` unique | Player profile retained until deletion |
| `/v1/me/wallet` | starter grant check, player balance | 1-3 | 1 player row, optional ledger write | player PK, `coin_ledger.idempotency_key` | Wallet balance permanent |
| `/v1/me/wallet/ledger` | ledger page by player/time | 1 | bounded by LIMIT | `coin_ledger_player_created_idx` | Ledger permanent minimal |
| matchmaking queue | active match lookup, queue cleanup, opponent lookup, funded match writes | 3-8 | active rows and bounded queue candidates | `matches_active_player_*`, `ranked_queue_open_match_idx` | Queue transient, stale after 2 minutes |
| active match | active match lookup by participant | 1 | active matches only | `matches_active_player_*` | Compact match result permanent |
| friends | accepted/pending friendship joins | 1 | LIMIT 100-200 | friendship PK/status indexes | In-game relationship until deletion |
| player search | normalized username prefix/search, friendship status | 1 | LIMIT 20 | `players_username_search_idx`, friendship PK | No new retention |
| challenges | pending list, create/respond updates | 1-4 | LIMIT 50 for lists | `challenges_*_status_idx` | Terminal 30 days |
| rematches | pending list, create/respond updates | 1-5 | pending rows only | `rematch_pending_recipient_idx` | Terminal 30 days |
| leaderboards | top/around-me rating rows | 2-3 | bounded page size | `player_ratings_stable_leaderboard_idx` | Rating permanent |
| match history | terminal matches by player | 1-2 | bounded page size | `matches_history_player_*` | Compact result permanent |
| rating | player ratings by scope | 1 | small fixed scope set | player rating PK | Permanent source of truth |
| purchase verify | purchase dedupe, grant, ledger, player balance | 3-5 | 1 dedupe row, 1 grant row | purchase unique indexes | Permanent minimal dedupe |
| rewarded ads | reward prepare/confirm dedupe, ledger, balance | 2-5 | 1 claim row | reward unique/token indexes | Unused tokens 7 days |
| account deletion | tombstone, active match guard, player cascade | 2-4 | bounded by player data | player PK, tombstone PK | Tombstone permanent minimal |

Rows read/written above are expectations from local code inspection. Exact Cloudflare `rows_read` and `rows_written` must come from D1/Workers telemetry or `wrangler d1 insights`; no percent savings are claimed without those measurements.

## Retention Matrix

| Data type | Source of truth | Retention | Cleanup method | Index | User impact |
| --- | --- | --- | --- | --- | --- |
| Durable Object match state | Durable Object storage | settlement + 15 minutes target | room alarm cleanup path; policy documented for full DO cleanup implementation | DO storage key | Reconnect grace preserved before cleanup |
| Compact match result | D1 `matches`, `match_players` | permanent | none | match/player indexes | Match history remains |
| Wallet balance | D1 `players.online_coins` | permanent until account deletion | none | player PK | Fast wallet reads |
| Wallet ledger | D1 `coin_ledger` | permanent minimal | none | `coin_ledger_player_created_idx` | Audit and recovery preserved |
| Purchase/SSV dedupe | D1 `purchase_grants`, SSV rows | permanent minimal | none | unique transaction/hash indexes | Replay protection preserved |
| Ranked queue | D1 `ranked_queue` | stale after 2 minutes | existing queue cleanup | `ranked_queue_open_match_idx` | Matchmaking freshness preserved |
| Terminal challenge | D1 `challenges` | 30 days | scheduled cleanup, max 500-1000 rows/run | `challenges_terminal_cleanup_idx` | Pending/accepted preserved |
| Terminal rematch | D1 `rematch_invitations` | 30 days | scheduled cleanup, max 500-1000 rows/run | `rematch_terminal_cleanup_idx` | Pending preserved |
| Rate limits | D1 `request_limits` | 48 hours | scheduled cleanup | `request_limits_window_idx` | Current abuse windows preserved |
| Disabled device tokens | D1 `device_tokens` | 7 days | scheduled cleanup | `device_tokens_disabled_cleanup_idx` | Active push tokens preserved |
| Unused ad preparation token | D1 `reward_claims` | 7 days | scheduled cleanup | `reward_claims_expired_cleanup_idx` | Claim idempotency preserved during validity |
| Transient audit | D1 `match_audit` | 30 days | scheduled cleanup | `match_audit_retention_idx` | Security audit retained short-term |
| Future tournament attempt | Future D1 tables | 90 days planned | future scheduled cleanup | future attempt status/time index | Not implemented in this phase |
| Account deletion tombstone | D1 `deleted_accounts` | permanent minimal | none | tombstone PK | Re-creation block preserved |

## Query and Index Decisions

Added indexes are limited to hot predicates already present in code:

- `ranked_queue_open_match_idx`: narrows open queue lookup by difficulty and `room_id IS NULL`.
- `matches_active_player_a_idx` / `matches_active_player_b_idx`: active-match polling and duplicate active-match prevention.
- `matches_history_player_a_idx` / `matches_history_player_b_idx`: terminal match history without scanning active rows.
- `challenges_terminal_cleanup_idx`, `rematch_terminal_cleanup_idx`, `request_limits_window_idx`, `reward_claims_expired_cleanup_idx`, `device_tokens_disabled_cleanup_idx`, `match_audit_retention_idx`: scheduled cleanup scans.

Write/storage cost: each new index adds write amplification for inserts/updates on its table. The added indexes target bounded hot reads and cleanup deletes; if DAU remains low and telemetry shows no pressure, these can be deferred before remote migration.

## Durable Object Write Policy

- `ping` and `request_snapshot` do not persist room state.
- Duplicate/no-op client messages do not persist unless the duel revision changes.
- Mutating messages still persist.
- Alarm writes are skipped when the computed next deadline is unchanged.
- Hibernatable WebSocket behavior is preserved.
- Settlement cleanup target is settlement + 15 minutes; full `deleteAll` room cleanup should be validated with live Durable Object storage tests before production enforcement.

## Leaderboard and Client Cache Policy

- Leaderboard queries must use bounded LIMIT and cursor pagination.
- Around-me remains separate from top-page queries.
- Wallet/profile client cache can use a short TTL, but must invalidate after Coin, purchase, match settlement, profile update, or manual refresh.
- Never show stale Coin after a confirmed mutation response.

## DAU Risk Estimates

| Scale | Free/Paid risk | Main pressure | Guardrail |
| --- | --- | --- | --- |
| 1,000 DAU | Low to moderate | active-match polling, queue churn, push tokens | indexed active queries, no-op DO write skip |
| 10,000 DAU | Moderate | leaderboard, ledger, challenge/rematch terminal rows | cursor pagination, scheduled cleanup, bounded LIMIT |
| 100,000 DAU | High | D1 reads/writes, DO alarms/storage, notification fanout | feature flags for matchmaking push, leaderboard cache, stricter cleanup batches |

These are qualitative risk levels, not savings claims.

## Feature Flag Shutdown Plan

- Disable matchmaking WebSocket push first and keep polling fallback.
- Disable public leaderboard refresh frequency before gameplay features.
- Keep wallet, purchase verification, settlement, and account recovery online.
- Keep offline Sudoku independent of App Check, platform identity, and online service availability.
