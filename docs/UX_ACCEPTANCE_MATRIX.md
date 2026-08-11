# UX Acceptance Matrix

| Criterion | Evidence target | Status |
| --- | --- | --- |
| One visible timer in active online duel | Widget test and code audit | Planned in 0B |
| Turn banner removed | No `_TurnBanner` usage or class | Planned in 0B |
| No ELO in player cards | Player plate omits rating badge | Planned in 0B |
| Board not grayscale on opponent turn | No active-game `ColorFiltered` dimming | Planned in 0B |
| Timer does not rebuild board each second | Timer scoped to header widget | Planned in 0B |
| Global text scale clamp removed | No `MediaQuery.copyWith(textScaler: clamp)` in online screen | Planned in 0B |
| Number pad minimum target met | Number buttons min 48 dp | Planned in 0B |
| Home has one primary action | Home hero has one filled action | Planned in 0B |
| Four top-level navigation sections | Home, Play, Compete, Profile shell | Planned in 0B |
| Account protection hidden from main UI | No Home banner or shield action | Planned in 0B |
| Replay absent | Result actions omit replay | Existing and retained |
| Light, dark, high contrast usable | Theme tokens and widget tests | Planned in 0B |
| 320x568 critical overflow absent | Widget tests | Planned in 0B |
| Text scale 2.0 usable | Widget tests | Planned in 0B |
| Backend/economy unchanged | No schema or settlement edits | Guardrail |
