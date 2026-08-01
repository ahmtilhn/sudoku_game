# Focused Product Scope

Sudoku Duel's visible product architecture is limited to two primary game modes:

- Career: the offline, progression-first Sudoku mode.
- Online Duel: the server-authoritative competitive match mode.

The first screen must not expose a Home/Play/Compete/Profile tab architecture, bottom navigation, tournament hub, country competition hub, clan hub, replay entry point, chat entry point, or placeholder community surface.

Supporting surfaces may be reachable through compact actions:

- Coin Store
- Profile
- Statistics when implemented
- Settings

Backend code for dormant or future systems may remain when it is not linked from the main player flow. New UI for tournaments, replay, clans, country competition, or chat is out of scope for this milestone.

