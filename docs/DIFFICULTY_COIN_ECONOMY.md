# Difficulty Coin Economy

Online Duel entry fees are server-authoritative and keyed by selected difficulty.

| Difficulty | Entry fee | Winner pot |
| --- | ---: | ---: |
| beginner | 100 | 200 |
| easy | 150 | 300 |
| medium | 250 | 500 |
| hard | 400 | 800 |
| expert | 650 | 1300 |

Rules:

- The client sends only the selected difficulty.
- The backend derives the entry fee and pot.
- Ranked matchmaking, funded matches, direct challenges, rematches, escrow, settlement, payout, and refund logic must use the difficulty-derived fee.
- Wallet snapshots expose `entryFees` and `minimumOnlineBalance`.
- Legacy fixed-fee constants may remain only as compatibility aliases for beginner/minimum behavior.

The client must not be trusted for Coin balances, entry fees, pots, score, ELO, or rewards.

