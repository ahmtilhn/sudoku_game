# Ranked Rating System

Initial rating is `1000`.

Ranked matches update two scopes:

- `global`
- the played difficulty: `beginner`, `easy`, `medium`, `hard`, or `expert`

Friendly challenge matches are unranked by default.

## Elo

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

Ratings are clamped to `100..3000` and rounded to integers. Score difference is
not included in rating deltas.

## Settlement

Settlement is intended to be idempotent through `match_settlements` and
`matches.rating_settled_at`. Ratings must not be applied twice for the same
match. Remote integration testing must specifically verify retry behavior before
production.

## Leaderboards

Ordering:

1. rating descending
2. games played descending
3. updated timestamp ascending

The backend exposes `/v1/leaderboards/:scope` and `/v1/me/ratings`.

