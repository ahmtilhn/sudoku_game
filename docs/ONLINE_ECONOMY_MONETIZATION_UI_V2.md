# Online Economy, Monetization, Rematch and Responsive UI V2

## 1. Product goals

This specification extends the server-authoritative online duel with:

- a clear active-turn visual state;
- a 100 Coin entry fee from each player and a 200 Coin winner pot;
- a 1,000 Coin starter grant;
- a consumable Coin Store from 100 to 100,000 Coins;
- daily login, rewarded-ad and achievement rewards;
- a complete result/rematch/new-match flow;
- a simple, responsive Material 3 UI;
- account, purchase, wallet and anti-abuse protections.

All wallet mutations, matchmaking entry checks, escrow, refunds, payouts, purchase grants and reward claims are server-authoritative. The Flutter client only displays server state and requests actions.

## 2. Required policy-safe product decisions

### 2.1 Coins

Coins are closed-loop virtual currency:

- usable only inside Sudoku Duel;
- not cashable, withdrawable, transferable, giftable or convertible to real-world value;
- never described as money, betting credit, wager or earnings;
- purchased Coin balances do not expire;
- store prices are always read from Google Play or App Store and are never hardcoded.

### 2.2 Competitive entry fee

The online flow is presented as a fixed game entry fee, not gambling:

- each accepted player contributes exactly 100 Coins;
- the server places 200 Coins into match escrow;
- winner receives the full 200 Coin pot, and the client displays balances refreshed from the wallet endpoint rather than trusting WebSocket payloads as the source of truth;
- draw refunds 100 Coins to each player;
- cancellation before an active game refunds both players;
- a valid forfeit or disconnect loss after the game starts awards the pot to the winner;
- no random prize, multiplier, loot box, cash prize or real-world reward exists.

### 2.3 Ads

- The daily +50 Coin rewarded ad is explicitly opt-in.
- Career rewarded interstitials are shown only after the result state, never during play or before the intended level starts.
- Before a rewarded interstitial, show an intro sheet with the exact reward and a Skip action.
- Rewards are granted only after the ad SDK reward callback, preferably confirmed with AdMob server-side verification.
- Development and automated tests use test ad unit IDs.

## 3. Economy constants

Initial server-configured defaults:

| Key | Default |
|---|---:|
| Starter grant | 1,000 Coins |
| Ranked entry fee per player | 100 Coins |
| Ranked winner pot | 200 Coins |
| Daily login reward | 50 Coins |
| Daily opt-in rewarded-ad reward | 50 Coins |
| Career rewarded-interstitial bonus | 25 Coins |
| Rematch response window | 10 seconds |
| Minimum online balance | 100 Coins |

All reward values must be remotely configurable without requiring a store release. Entry fee and pot changes require protocol/version compatibility checks.

## 4. Starter grant and account durability

The starter grant is once per durable player account, not once per reinstall. Granting on every anonymous reinstall would allow unlimited farming.

Required identity behavior before production economy is enabled:

- keep anonymous sign-in for immediate onboarding;
- link or upgrade it to a durable account using supported platform identity/account flows;
- preserve the same backend player and wallet when the account is linked;
- store an idempotent `starter_grant:<player_id>` ledger key;
- use Firebase App Check and platform/device risk signals to reduce automated account farming;
- do not reset Coins when the app is reinstalled or moved to another device.

## 5. Server wallet and ledger

### 5.1 Source of truth

`players.online_coins` may remain as a cached balance, but every mutation must also create an immutable ledger record.

Proposed tables:

```sql
CREATE TABLE coin_ledger (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL,
  amount INTEGER NOT NULL,
  balance_after INTEGER NOT NULL,
  reason TEXT NOT NULL,
  reference_type TEXT,
  reference_id TEXT,
  idempotency_key TEXT NOT NULL UNIQUE,
  metadata_json TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
);

CREATE INDEX coin_ledger_player_created_idx
  ON coin_ledger(player_id, created_at DESC);

CREATE TABLE match_coin_escrow (
  match_id TEXT PRIMARY KEY,
  player_a_id TEXT NOT NULL,
  player_b_id TEXT NOT NULL,
  player_a_amount INTEGER NOT NULL CHECK(player_a_amount = 100),
  player_b_amount INTEGER NOT NULL CHECK(player_b_amount = 100),
  pot_amount INTEGER NOT NULL CHECK(pot_amount = 200),
  status TEXT NOT NULL CHECK(status IN ('funded','paid','refunded')),
  winner_id TEXT,
  funded_at TEXT NOT NULL,
  settled_at TEXT,
  FOREIGN KEY(match_id) REFERENCES matches(id) ON DELETE CASCADE
);
```

### 5.2 Ledger reasons

Minimum supported reasons:

- `starter_grant`
- `match_entry`
- `match_payout`
- `match_refund`
- `daily_login`
- `daily_rewarded_ad`
- `career_rewarded_ad`
- `achievement_reward`
- `store_purchase`
- `purchase_refund`
- `admin_adjustment`

### 5.3 Safety rules

- No client-provided balance or reward amount is trusted.
- Every mutation has a unique idempotency key.
- Balance may never become negative through ordinary gameplay.
- Match creation, both 100 Coin deductions, escrow creation and room creation are one transactional operation.
- If either player has less than 100 Coins, the transaction fails and neither player is charged.
- Settlements are idempotent and can run repeatedly without duplicate payout.
- Refund and chargeback processing may reduce the wallet and can lock paid entry until resolved, but must never silently delete ledger history.

## 6. Matchmaking and escrow lifecycle

### 6.1 Queue entry

- Before joining, fetch the server wallet balance.
- Below 100 Coins: do not enter the queue; show an insufficient-Coins sheet with Coin Store, daily reward and menu actions.
- Queue join itself does not charge Coins.
- Search cancellation does not charge Coins.

### 6.2 Match creation

When a compatible opponent is found:

1. Recheck both balances.
2. Deduct 100 Coins from player A.
3. Deduct 100 Coins from player B.
4. Create a funded 200 Coin escrow record.
5. Create the match and room.
6. Return the room ID and both current balances.

These operations must be serialized by the matchmaking Durable Object and committed transactionally in D1.

### 6.3 Settlement

- Winner: +200 Coins from escrow.
- Loser: no additional deduction at settlement.
- Draw: +100 Coins refund to each player.
- Cancelled before active: +100 Coins refund to each player.
- Forfeit/disconnect after active: winner receives +200 Coins.
- Settlement updates match state, ledger, escrow status and wallet balances atomically.

## 7. Turn-state UI

### 7.1 Active local turn

- Board, score cards and number pad use normal theme colors.
- The local player card and turn banner use a stronger primary emphasis.
- Number pad and editable cells are enabled.
- Optional short haptic and subtle sound fire only when the turn changes from opponent to local.

### 7.2 Opponent turn

- Apply an animated grayscale/desaturated treatment to the playable game area.
- Reduce opacity slightly, while keeping text contrast accessible.
- Disable board and number-pad interaction with `IgnorePointer`.
- Keep a clear non-color cue: `Rakibin sırası` plus remaining turn time.
- Do not repeatedly show a Snackbar when the disabled board is tapped.
- Connection errors, countdowns and accessibility announcements remain visible.

### 7.3 Transition

- Use a 200–300 ms animation.
- Do not apply the grayscale mode during waiting/ready state or after the match finishes.
- A turn change must update both clients from the same authoritative server snapshot.

## 8. Result, rematch and new-match flow

The current one-button result dialog is replaced with a responsive result surface.

### 8.1 Content

- win/loss/draw title;
- opponent name;
- final score;
- entry fee, pot and payout/refund summary;
- Coin balance before/after;
- rating change;
- finish reason;
- connection/settlement status when still syncing.

### 8.2 Actions

1. `Tekrar meydan oku`
2. `Yeni eşleşme bul`
3. `Arkadaş olarak ekle`
4. `Menüye dön`

Rules:

- Rematch and new match are enabled only when current server balance is at least 100 Coins.
- Exactly 100 Coins is sufficient.
- Below 100 Coins, disable these actions and show the Coin Store/reward route.
- Friend action is hidden or replaced with status when already friends or request is pending.

### 8.3 Ten-second rematch invitation

- Sender creates a short-lived rematch invitation tied to the completed match and same opponent.
- Recipient receives an in-app overlay and push notification when available.
- Recipient has 10 seconds to accept or reject.
- Accept rechecks both balances and creates a new funded match.
- Reject returns `Meydan okuma reddedildi`.
- Timeout returns `Meydan okuma süresi doldu`.
- No Coins are deducted until acceptance creates the new match.
- Duplicate taps and duplicate notifications are idempotent.
- Leaving the result screen does not cancel a sent invitation unless explicitly cancelled.

### 8.4 New matchmaking

- `Yeni eşleşme bul` returns to matchmaking with the previous difficulty preselected.
- It does not automatically charge Coins until an opponent is actually paired.

## 9. Coin Store

### 9.1 Consumable product catalog

| Product ID | Coins | UI label |
|---|---:|---|
| `coins_100` | 100 | Başlangıç |
| `coins_500` | 500 | Küçük Paket |
| `coins_1000` | 1,000 | Standart |
| `coins_5000` | 5,000 | Popüler |
| `coins_10000` | 10,000 | Büyük Paket |
| `coins_50000` | 50,000 | Mega Paket |
| `coins_100000` | 100,000 | Ultimate |

Store rules:

- Android uses Google Play one-time consumable products.
- iOS uses App Store consumable In-App Purchases.
- Product title, description, currency and price come from the storefront.
- Do not display a fake crossed-out price or bonus percentage unless the store configuration genuinely supports it.
- Purchase receipt/token is sent to the backend.
- Backend verifies the transaction with the relevant store, checks product ID and purchase state, then grants Coins exactly once.
- Android purchase is acknowledged/consumed only after successful server grant.
- Keep purchase transaction IDs in a unique table to block replay.
- Handle pending, cancelled, failed, refunded and chargeback states.

## 10. Daily rewards

### 10.1 Daily login

- +50 Coins once per server-defined day.
- Show a small claim card after startup, not an unavoidable full-screen interruption.
- Claim is server-authoritative and idempotent.
- Show the next eligibility countdown.
- Missing a day does not remove purchased or earned Coins.

### 10.2 Daily rewarded ad

- One opt-in rewarded ad per server-defined day.
- Reward: +50 Coins.
- Button shows availability, reward and cooldown.
- Grant only from the verified reward callback/SSV event.
- Ad unavailable: keep the rest of the app usable and show a retry message.

## 11. Achievement rewards

Achievement rewards are backend-owned and one-time per achievement ID.

Suggested initial tiers:

| Tier | Reward |
|---|---:|
| Bronze | 50 Coins |
| Silver | 100 Coins |
| Gold | 250 Coins |
| Platinum | 500 Coins |
| Special/Milestone | 1,000 Coins |

- Native Play Games/Game Center achievements may mirror the backend achievement state, but must not be the only proof used to grant Coins.
- Each claim uses `achievement:<player_id>:<achievement_id>` as an idempotency key.
- Show earned reward in the achievement completion UI and wallet history.

## 12. Career completion ads

After each successful career puzzle:

1. Show the completion/result state first.
2. Present a rewarded-interstitial intro sheet: `Reklamı izle, +25 Coin kazan`.
3. Provide `İzle` and `Atla` actions.
4. If watched and the SDK confirms reward, grant +25 Coins through the backend.
5. Continue regardless of ad availability or skip.

Initial anti-fatigue and anti-abuse defaults:

- server-configurable daily career-ad reward cap;
- frequency and reward values controlled remotely;
- never show while the user is entering a number, during the puzzle, before a new level begins or over a purchase flow.

## 13. Social identity and discoverability

Include the existing player-identity scope:

- first online entry requires display-name confirmation;
- suggest Game Center or Google Play Games display name when available;
- allow a custom unique Sudoku Duel username;
- keep immutable public friend ID;
- show friend ID in Settings with Copy action;
- allow discoverability on/off;
- search by username, display name or exact friend ID;
- show opponent name throughout matchmaking, game, result, history and challenges;
- preserve recent opponents and direct challenges.

A durable identity is required before purchases and competitive wallet balances are production-enabled.

## 14. Responsive UI system

### 14.1 Layout rules

- Use available window constraints, not device-model checks.
- `LayoutBuilder` and `MediaQuery.sizeOf` drive breakpoints.
- Avoid fixed screen heights and hardcoded pixel assumptions.
- Keep every interactive target at least 48×48 logical pixels.
- Respect SafeArea, keyboard insets, display cutouts and large text.
- Do not force portrait orientation.

Suggested width classes:

- `< 360`: extra compact;
- `360–599`: phone;
- `600–839`: tablet/compact landscape;
- `>= 840`: expanded.

### 14.2 Result surface

- Narrow phone: modal bottom sheet with vertically stacked actions.
- Normal phone: compact dialog or bottom sheet.
- Tablet/landscape: centered dialog, maximum width about 480–560.
- No clipped actions at 200% text scale.

### 14.3 Coin Store

- extra compact: one column;
- phone: one or two columns depending on available width;
- tablet: two or three columns;
- expanded: centered content with bounded width, never stretched edge-to-edge.

### 14.4 Visual design

- Material 3 and the existing brand direction;
- simple surfaces, restrained elevation and consistent 8/12/16/24 spacing;
- one primary action per surface;
- avoid dense cards, excessive borders and repeated explanatory text;
- use color plus icon/text/state, never color alone;
- use adaptive switches and platform-appropriate system behaviors.

## 15. Required API additions

Suggested endpoints:

- `GET /v1/me/wallet`
- `GET /v1/me/wallet/ledger`
- `POST /v1/rewards/daily-login/claim`
- `POST /v1/rewards/daily-ad/prepare`
- `POST /v1/rewards/daily-ad/confirm`
- `POST /v1/rewards/career-ad/prepare`
- `POST /v1/rewards/career-ad/confirm`
- `POST /v1/achievements/:id/claim`
- `POST /v1/purchases/google/verify`
- `POST /v1/purchases/apple/verify`
- `POST /v1/matches/:id/rematch`
- `POST /v1/rematches/:id/respond`
- `GET /v1/rematches/pending`

Responses that can lead to play must include current balance and `canEnterOnline`.

## 16. Localization

All existing hardcoded Turkish online-duel strings and all new economy/store/reward/rematch strings must be moved into the localization system.

Minimum coverage:

- turn states;
- Coin balance and wallet history;
- insufficient Coins;
- entry fee and pot;
- store states and purchase errors;
- daily rewards;
- ad unavailable/skipped/rewarded;
- rematch accepted/rejected/timed out;
- settlement pending/complete;
- refund and chargeback states.

Pluralization and locale-formatted numbers/currencies are required. Store currency text must come from the storefront.

## 17. Test matrix

### 17.1 Economy

- new durable account receives exactly 1,000 Coins once;
- reinstall/relink does not grant another starter reward;
- balance 99 cannot queue;
- balance 100 can queue and rematch;
- queue cancellation costs zero;
- both players are charged exactly 100 when a match is created;
- winner receives exactly 200;
- draw/cancel refunds exactly 100 each;
- duplicate settlement does not duplicate payout;
- simultaneous wallet actions cannot create a negative balance;
- purchase token replay is rejected;
- daily and achievement rewards cannot be claimed twice.

### 17.2 Rematch

- accept within 10 seconds starts a new funded room;
- reject and timeout show different states;
- sender/recipient balance dropping below 100 fails without partial debit;
- duplicate accept cannot create two rooms;
- app background/foreground preserves countdown from server time;
- push and in-app invitation resolve to the same invitation.

### 17.3 Ads

- reward only after earned callback/SSV;
- skip grants no reward;
- no-fill does not block progress;
- test ad IDs in debug/test;
- no ad during gameplay or purchase flow;
- daily cap and career cap are enforced server-side.

### 17.4 Responsive/accessibility

Test at minimum:

- 320×568, 360×800, 390×844, 430×932;
- Android tablet and iPad widths;
- portrait, landscape, split-screen and foldable window sizes;
- text scale 1.0, 1.3 and 2.0;
- TalkBack and VoiceOver;
- grayscale/color-vision testing;
- RTL layout;
- offline, slow network and reconnect states.

### 17.5 Cross-platform

- Android ↔ Android;
- iOS ↔ iOS;
- Android ↔ iOS;
- simultaneous matchmaking requests;
- queue cancel/rejoin;
- disconnect, reconnect, timeout, forfeit and app termination;
- store sandbox/test purchases on both platforms.

## 18. Implementation phases

1. Turn-state visual treatment and result-surface refactor.
2. Wallet ledger, starter grant and wallet endpoints.
3. Transactional match escrow, refund and payout.
4. Ten-second rematch and new-match flows.
5. Responsive Coin Store UI and storefront catalog integration.
6. Server-side Google Play/App Store purchase verification.
7. Daily login, daily rewarded ad and career rewarded interstitial.
8. Achievement rewards.
9. Player identity, friend ID and discoverability completion.
10. Localization, accessibility, test automation and production hardening.

## 19. Release gates

Do not mark production-ready until:

- all wallet and purchase mutations are server-authoritative and idempotent;
- real store products exist and sandbox/test purchases pass;
- App Check and purchase verification are enabled in production;
- the matchmaking and escrow race tests pass;
- Android/iOS cross-platform evidence passes;
- ads follow consent, rewarded and disruptive-ad policies;
- privacy policy and store disclosures include ads, purchases, account identity and virtual currency;
- staging and production databases/workers are separate;
- review notes explain account, Coin, reward, ad and online-match behavior.
