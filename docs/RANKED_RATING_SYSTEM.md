# Ranked MMR + Rank Points System

This document is the authoritative competitive progression contract for the current Sudoku Duel release.

The competitive system has **two separate server-owned numbers**:

1. **Hidden Elo / MMR** — skill estimate used by the existing matchmaking and rating settlement.
2. **Visible Rank Points (RP)** — player-facing progression used for Bronze III through Master I, rank frames, first-time rank rewards and the in-app RP leaderboard.

The two systems must not be merged. The existing online duel authority remains unchanged.

## 1. Hidden Elo / MMR

The existing rating starts at `1000` and remains the skill signal for matchmaking.

Ranked matches update the existing scopes:

- `global`
- the played difficulty: `beginner`, `easy`, `medium`, `hard`, or `expert`

Friendly challenge matches remain unranked by default.

### Elo formula

Expected score:

```text
Ea = 1 / (1 + 10 ^ ((Rb - Ra) / 400))
```

Result values:

- win: `1.0`
- draw: `0.5`
- loss: `0.0`

K-factor:

- first 20 rated games: `40`
- games 21-100: `24`
- after 100 games: `16`

Hidden ratings are clamped to `100..3000` and rounded to integers. Sudoku score difference, solve speed and margin of victory do not add extra Elo.

### Hidden-MMR authority boundary

The following existing systems stay authoritative and must not be replaced by the RP layer:

- ranked matchmaking queue
- GameRoom / Durable Object result authority
- WebSocket duel protocol
- puzzle state and validation
- match settlement
- existing Elo settlement
- match Coin escrow / payout / refund

The RP layer reads the already-settled result and the pre-match hidden-MMR snapshots. It does not decide who won and does not modify the authoritative online result.

## 2. Visible Rank Points

Every player begins visible competitive progression at:

```text
0 RP = Bronze III
```

Existing players also begin the new visible ladder from zero at the RP-system epoch. Old hidden Elo is not converted into free visible RP.

### Rank ladder

| Rank | RP range | Target hidden MMR | First-time Coin reward |
|---|---:|---:|---:|
| Bronze III | 0-299 | 1000 | 0 |
| Bronze II | 300-599 | 1100 | 250 |
| Bronze I | 600-899 | 1200 | 350 |
| Silver III | 900-1199 | 1300 | 600 |
| Silver II | 1200-1499 | 1400 | 450 |
| Silver I | 1500-1799 | 1500 | 550 |
| Gold III | 1800-2099 | 1600 | 900 |
| Gold II | 2100-2399 | 1700 | 650 |
| Gold I | 2400-2699 | 1800 | 750 |
| Platinum III | 2700-2999 | 1900 | 1200 |
| Platinum II | 3000-3299 | 2000 | 850 |
| Platinum I | 3300-3599 | 2100 | 950 |
| Master III | 3600-3899 | 2200 | 1500 |
| Master II | 3900-4199 | 2300 | 1200 |
| Master I | 4200+ | 2400+ | 1800 |

Each normal division is `300 RP`. Master I has no visible upper cap; its continuing RP value determines high-end leaderboard ordering.

Total lifetime first-time rank rewards:

```text
12,000 Coin
```

Rank rewards are lifetime-first-time rewards. Dropping from a division and climbing back into it must never grant the Coin reward again.

## 3. RP result table

Visible RP is calculated from the opponent's **pre-match hidden MMR relative to the player's pre-match hidden MMR**.

| Opponent relative MMR | Win | Draw | Loss |
|---|---:|---:|---:|
| 251+ lower | +10 | -15 | -40 |
| 151-250 lower | +12 | -12 | -36 |
| 76-150 lower | +18 | -6 | -30 |
| within ±75 | +24 | 0 | -24 |
| 76-150 higher | +30 | +6 | -18 |
| 151-250 higher | +36 | +12 | -12 |
| 251+ higher | +40 | +15 | -10 |

This prevents a strong player from gaining the same RP for beating a much weaker opponent as for beating an equal or stronger opponent.

## 4. MMR-to-rank alignment modifier

The visible rank has a target hidden MMR. If hidden skill is substantially ahead of or behind visible rank, RP gain/loss is adjusted so the player converges toward the appropriate visible level.

| Hidden MMR versus current rank target | Positive RP | Negative RP |
|---|---:|---:|
| within ±99 | 100% | 100% |
| +100 to +199 | 110% | 90% |
| +200 or more | 125% | 75% |
| -100 to -199 | 90% | 110% |
| -200 or less | 75% | 125% |

Values are rounded to integer RP after the percentage is applied.

This is a catch-up/correction mechanism, not a matchmaking replacement.

## 5. Same-opponent anti-farm

Positive RP is reduced when the same pair repeatedly plays within a rolling 24-hour window:

- first match: `100%` positive RP
- second match: `100%` positive RP
- third match: `50%` positive RP
- fourth and later matches: `0%` positive RP

Negative RP is **never softened** by the repeat-opponent rule.

The intent is to prevent two accounts from trading wins to farm rank while still allowing ordinary rematches.

## 6. Forfeit / disconnect penalty

A ranked loss caused by any of the following receives the normal RP loss plus an additional `-8 RP` abandonment penalty:

- explicit forfeit
- disconnect forfeit
- consecutive timeout forfeit

RP never drops below zero.

Server/system cancellations that do not produce an authoritative rated loss must not invent an RP loss.

## 7. No performance or streak RP bonuses

Do **not** grant additional RP for:

- faster Sudoku completion
- larger score margin
- more correctly filled cells
- perfect-game speed
- win streaks

Sudoku performance determines the authoritative match result under existing duel rules. RP then uses only result + hidden-MMR relationship + alignment + anti-farm + abandonment rules.

Win streaks, perfect games and other milestones may unlock achievements and cosmetics, but they do not directly multiply RP.

## 8. Rank frames and player identity

Every division has its own rank frame:

- Bronze III / II / I
- Silver III / II / I
- Gold III / II / I
- Platinum III / II / I
- Master III / II / I

A frame permanently unlocks once the player has reached that rank. The player may later equip any previously unlocked frame even if current RP is lower.

The actual current rank remains separately visible, so equipping an old prestigious frame cannot spoof current competitive standing.

The identity system supports:

- built-in game-relevant avatar presets
- optional local Game Center / Google Play Games avatar presentation
- one equipped rank frame
- up to three equipped achievement decorations
- unlocked rank titles such as Master / Master I

Server composite avatar identity is encoded so normal player cards can display the selected avatar, frame and equipped decorations without changing matchmaking or duel protocol authority.

## 9. Achievement decorations

Ranked progression currently supports frame decorations for milestones including:

- undefeated 10 / 25 / 50
- win streak 5 / 10 / 25
- reach Silver / Gold / Platinum / Master / Master I
- Giant Slayer: beat an opponent at least 251 hidden-MMR points above you
- ranked games 100 / 500 / 1000
- perfect ranked win
- 10 perfect ranked wins

A player may equip at most three decorations at once.

Achievement decorations and earned rank frames are earned cosmetics. They are not store purchases.

## 10. Reward idempotency

Rank Coin rewards are protected by a database uniqueness boundary:

```text
PRIMARY KEY(player_id, rank_key)
```

The reward grant also uses a deterministic ledger idempotency key:

```text
rank_reward:<playerId>:<rankKey>
```

Therefore retries, profile refreshes, repeated result requests, rank drops and re-promotions cannot legitimately mint the same lifetime rank reward twice.

## 11. RP settlement and reconciliation

Visible RP settlement is intentionally additive:

1. the existing online match finishes and settles normally;
2. authoritative match result and hidden-MMR snapshots are already stored;
3. RP reconciliation reads those rows;
4. RP delta is stored idempotently per player/match;
5. post-settlement logic unlocks reached rank rewards / achievements and refreshes the composite frame identity;
6. Flutter reads the player-facing RP result for the result screen.

The rank result endpoint must never be required for the match itself to finish. If the RP service is temporarily unavailable, the authoritative online duel result remains valid.

## 12. Leaderboards

The main **in-app competitive ladder** is ordered by visible Rank Points, with deterministic tie breakers. The player sees rank tier + RP rather than hidden Elo.

Legacy/native platform leaderboard integrations may continue to exist as isolated compatibility surfaces, but they do not define the in-app visible rank.

## 13. Friendly challenges

Friendly challenge matches remain unranked unless the product explicitly introduces a separate rated challenge mode in a future version.

They must not mutate visible RP merely because the same online duel board/protocol is reused.

## 14. Safety rule for future development

Any future season, tournament, clan or social feature must treat these as separate concepts:

```text
Hidden MMR = skill / matchmaking signal
Visible RP = player-facing competitive progression
Current Rank = tier derived from visible RP
Cosmetic Frame = unlocked/equipped identity item
Achievement Decoration = optional earned frame attachment
```

Do not make client-supplied RP, hidden MMR, Coin reward amounts, rank unlocks or achievement unlocks authoritative.
