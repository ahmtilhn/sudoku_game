# Visible RP Rank and Player Identity System

This document is the implementation lock for the player-facing competitive progression and profile identity layer. It intentionally sits **on top of** the existing authoritative online duel system.

## Non-negotiable architecture boundary

The existing online duel core remains authoritative and must not be rewritten for this feature:

- `GameRoom` Durable Object remains the authority for room state.
- The WebSocket protocol, revisions, move validation, turns, disconnect handling and timeout handling remain unchanged.
- Existing 1000-based Elo remains the hidden matchmaking skill signal (MMR).
- Existing matchmaking queue semantics remain unchanged.
- Existing match settlement remains authoritative.
- Existing Coin escrow, entry fees, payout and refund rules remain unchanged.
- Visible RP is reconciled **after** an authoritative ranked match settlement exists.

Visible RP must never become an input to the room engine. Hidden MMR must never be exposed through the new RP APIs or UI.

## Two-layer competitive model

### Hidden MMR

The current Elo implementation starts at 1000 and continues to update with the existing Elo formula/K-factor. It is retained as an internal skill estimate for matchmaking and competitive balancing.

The player-facing UI must not call this number RP and must not present it as the player's visible rank progress.

### Visible Rank Points (RP)

Every account begins its visible competitive journey at **0 RP / Bronze III**. RP is the only number used for the new displayed division ladder.

| Division | RP range | Target hidden MMR | First-time Coin reward |
|---|---:|---:|---:|
| Bronze III | 0–299 | 1000 | 0 |
| Bronze II | 300–599 | 1100 | 250 |
| Bronze I | 600–899 | 1200 | 350 |
| Silver III | 900–1199 | 1300 | 600 |
| Silver II | 1200–1499 | 1400 | 450 |
| Silver I | 1500–1799 | 1500 | 550 |
| Gold III | 1800–2099 | 1600 | 900 |
| Gold II | 2100–2399 | 1700 | 650 |
| Gold I | 2400–2699 | 1800 | 750 |
| Platinum III | 2700–2999 | 1900 | 1200 |
| Platinum II | 3000–3299 | 2000 | 850 |
| Platinum I | 3300–3599 | 2100 | 950 |
| Master III | 3600–3899 | 2200 | 1500 |
| Master II | 3900–4199 | 2300 | 1200 |
| Master I | 4200+ | 2400+ | 1800 |

The fourteen first-time promotion rewards total exactly **12,000 Coin**. Rank rewards are lifetime, idempotent account unlocks. Falling below a division and reaching it again never grants its Coin reward again.

Master I has no visible RP ceiling. Players continue competing by RP on the leaderboard after 4200.

## RP result table

Base RP is selected from the hidden MMR difference `opponentMMR - playerMMR`.

| Opponent MMR difference | Win | Draw | Loss |
|---|---:|---:|---:|
| `<= -251` | +10 | -15 | -40 |
| `-250..-151` | +12 | -12 | -36 |
| `-150..-76` | +18 | -6 | -30 |
| `-75..+75` | +24 | 0 | -24 |
| `+76..+150` | +30 | +6 | -18 |
| `+151..+250` | +36 | +12 | -12 |
| `>= +251` | +40 | +15 | -10 |

A player is therefore rewarded more for beating a stronger opponent and penalized more for losing to a substantially weaker opponent.

## Visible-rank catch-up correction

The hidden MMR is compared with the target MMR of the player's current visible division. This prevents strong new players from remaining in low visible ranks for an excessive number of matches and prevents visible rank from drifting permanently above actual skill.

| Hidden MMR vs current division target | Positive RP | Negative RP |
|---|---:|---:|
| within ±99 | 100% | 100% |
| +100..+199 | 110% | 90% |
| +200 or more | 125% | 75% |
| -100..-199 | 90% | 110% |
| -200 or less | 75% | 125% |

Rounding is deterministic and the final visible RP floor is zero.

## Repeat-opponent anti-farm protection

Within a rolling 24-hour window, positive RP against the same opponent is reduced as follows:

- first match: 100%
- second match: 100%
- third match: 50%
- fourth and later: 0%

Negative RP is never softened by repeat-opponent protection. This prevents coordinated RP farming without letting players intentionally rematch to reduce the cost of losses.

## Match outcome rules

- Ranked match completed normally: use the RP table.
- Ranked explicit forfeit after start: normal loss RP plus **-8 RP** abandonment penalty.
- Ranked disconnect forfeit after start: normal loss RP plus **-8 RP** abandonment penalty.
- Ranked forfeit from three consecutive timeouts: normal loss RP plus **-8 RP** abandonment penalty.
- Friendly match: **0 RP**.
- Pre-start cancellation: **0 RP**.
- Server-side cancellation/refund: **0 RP**.
- No extra RP is awarded for Sudoku score margin, speed, correct-cell count or mistake margin.
- No win-streak RP multiplier exists.

The Sudoku game score determines the authoritative winner. It does not independently multiply RP.

## Settlement and idempotency

`rank_progression_settlements` is a derived audit/read-model table keyed by `(match_id, player_id)`. Reconciliation reads only already-authoritative ranked match/player rows. The RP layer cannot settle the same player/match twice.

Rank Coin rewards are keyed by `(player_id, rank_key)`. Their ledger idempotency key is also account/rank specific, making first-time rewards non-farmable.

The RP rollout epoch prevents historic matches from unexpectedly generating a new visible ladder/reward history when the feature is first enabled.

## Player identity model

A visible player identity has four independent layers:

1. **Avatar** — selectable built-in game avatar or approved legacy/platform source.
2. **Rank frame** — one of the 15 earned division frames, or `Auto` to follow the current rank.
3. **Achievement decorations** — up to three earned brooch/badge decorations attached to frame slots.
4. **Title** — optional permanent prestige title, currently focused on Master milestones.

The composite avatar key is a backwards-compatible presentation encoding. Existing plain avatar keys continue to render.

### Avatar catalog

The app ships with **96 built-in presets**. They are deliberately Sudoku/logic/game adjacent: grids, numbers, symbols, geometry, strategy objects, puzzle motifs, robots, masks, celestial/elemental puzzle motifs and other stylized game identities. The catalog does not depend on unrelated stock photography or third-party portrait licenses.

Preset keys are stable: `preset_001` through `preset_096`.

### Rank frames

Every visible division has its own frame:

- Bronze III / II / I
- Silver III / II / I
- Gold III / II / I
- Platinum III / II / I
- Master III / II / I

III is the entry visual within a league, II is richer, and I is the most prestigious form of the league family.

Reaching a division permanently unlocks that frame. `Auto` follows current rank; selecting an older earned frame is allowed. The current rank remains separately visible so historic cosmetics never misrepresent current competitive standing.

### Rank emblems

The app also owns a transparent/background-free emblem renderer for all 15 divisions. Emblems use league-specific metallic palettes, visible III/II/I marks, progressive wing/chevron detail and a central 3×3 Sudoku-grid motif.

### Achievement frame decorations

A profile may equip at most **three** unlocked achievement decorations at once. The slots are visual identity only; they do not alter matchmaking or RP math.

Initial decoration families include:

- First Victory
- 10 / 50 / 250 wins
- 25 games
- daily focus streak
- country contribution
- tournament podium
- friend/rival badge
- 10 / 25 / 50 ranked matches without a loss
- 5 / 10 / 25 ranked win streak
- Silver / Gold / Platinum / Master / Master I milestones
- Giant Slayer (defeat an opponent at least 251 hidden MMR above you)
- 100 / 500 / 1000 ranked-match veteran badges
- perfect ranked win / ten perfect ranked wins

`Unbeaten 50` is a legendary frame brooch and is awarded only after fifty consecutive ranked matches without a loss.

Rank frames and earned achievement decorations are not store purchases.

## Privacy

`/v1/competitive/rank-player/<publicId>` returns only public visible-RP summary fields for matchup presentation. It never returns hidden MMR.

For another player, the public summary respects profile discoverability. Private/non-discoverable users do not expose their RP/stat summary through this endpoint.

Raw Firebase or platform account identifiers are not part of the public rank response.

## UI presentation rules

Player-facing competitive surfaces should prefer:

- `Bronze III`, `Silver II`, etc.
- `1234 RP`
- progress to the next visible division
- current/peak visible rank
- earned rank frame and achievement decorations

They should not display the hidden 1000-based matchmaking value as the player's rank score.

The online result sheet requests visible RP only **after** the authoritative match result exists. If the additive RP request temporarily fails, the result/rematch/menu flow must remain usable and the RP read-model may reconcile on the next profile/leaderboard read.

## Explicit non-goals

Do not:

- replace hidden Elo with RP for matchmaking;
- move RP math into `GameRoom`;
- change WebSocket message semantics to implement RP;
- change existing Sudoku win determination for RP;
- change entry-fee escrow or winner payout for RP;
- grant RP from friendly matches;
- grant rank Coin rewards more than once per account/division;
- expose hidden MMR through public profile, matchup or result UI;
- sell earned rank frames or achievement brooches as if they were competitive accomplishments.
