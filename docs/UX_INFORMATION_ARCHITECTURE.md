# UX Information Architecture

## Goal

Sudoku Duel uses a four-section app shell for non-gameplay surfaces: Home, Play, Compete, and Profile. The shell keeps tab state stable, keeps Store and Settings out of the top-level navigation, and leaves gameplay screens full-screen so the board remains the primary focus.

## Top-Level Sections

| Section | Primary job | Primary action | Secondary actions | Canonical routes |
| --- | --- | --- | --- | --- |
| Home | Resume or start the next best activity | Quick Duel or Return to match | Daily reward, current progress, Coin balance | `/home` |
| Play | Offline and learning modes | Career | Classic Sudoku, Daily Sudoku, Practice, Tutorial | `/play`, `/career`, `/daily`, `/tutorial` |
| Compete | Online competition | Ranked matchmaking | Leaderboards, friends, challenges, recent matches | `/compete`, `/ranked`, `/leaderboards`, `/friends` |
| Profile | Player identity and settings | Player profile | Achievements, statistics, platform status, settings | `/profile`, `/settings` |

## Navigation Rules

- Compact and medium widths use Material 3 `NavigationBar`.
- Expanded widths use `NavigationRail`.
- Game screens are pushed above the shell and do not show bottom navigation.
- Store is opened from the Coin pill or Profile, not as a top-level tab.
- Settings is reachable from Profile, not as a top-level tab.
- Push notification handlers may deep-link directly to the target screen.
- Canonical routes should avoid uncontrolled chains of nested `MaterialPageRoute` pushes.

## Audit Summary

| Area | Current purpose | Primary issue found | 0B decision |
| --- | --- | --- | --- |
| Home | Entry point and economy summary | Too many equally weighted cards, visible account protection banner, shield action | Replace with one primary hero, compact quick modes, Coin pill, no account protection in main flow |
| Matchmaking | Ranked queue entry | AppBar has multiple social/leaderboard icons and difficulty cards are visually heavy | Keep behavior, move toward compact Compete-first hierarchy |
| Online Duel | Live online gameplay | Duplicate turn/timer banner, ELO badges in player cards, board dimmed on opponent turn, global text scale clamp | Remove banner/ELO, keep one timer, preserve board contrast, isolate timer updates |
| Board | Shared Sudoku interaction | Strong outer border and per-cell state mostly color-based | Keep shared component, add softer radius and multi-signal states |
| Number pad | Shared Sudoku input | Compact mode can create sub-48 dp targets and uses shrinkWrap for numbers | Maintain minimum 48 dp number targets |
| Profile/social/settings | Identity and account management | Profile/account flows can bleed into Home | Keep account protection backend, remove from main Home UI |

## Touch Targets

| Task | Target taps |
| --- | --- |
| Resume | 1 |
| Quick Duel | 1 |
| Daily Sudoku | 1 |
| Ranked difficulty | 2 or fewer |
| Leaderboard | 2 or fewer |
| Friend challenge | 3 or fewer |
| Profile | 1 |
| Settings | 2 or fewer |
