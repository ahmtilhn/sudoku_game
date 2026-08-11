# UI/UX Reference Spec

The app opens directly into a focused play lobby.

Primary actions:

- Career card: opens the career difficulty/progression flow.
- Online Duel card: opens matchmaking and shows the minimum online Coin entry requirement.

Secondary actions:

- Coin Store: visible as a compact balance action.
- Profile: opens the competitive profile only, without social search or community hubs.
- Settings: opens app preferences and player account controls.

Online Duel:

- Difficulty selection remains inside the matchmaking screen.
- Entry fee and winner pot are displayed from server-provided fee data.
- Friend/community/leaderboard shortcuts are not shown from the focused matchmaking surface.

No Ads:

- Players with the `no_ads` entitlement must not see rewarded ad offers.
- Ad SDK loading and show attempts must be blocked by the entitlement.

