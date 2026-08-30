# Complete UX Audit

This report inventories every production `*_screen.dart` file under `lib/features`. It combines source-level UX checks with the gameplay, profile, feedback, localization, error-safety, branch and release work completed on `main`.

## Audit scope

- Screen files: **33**
- Forwarding/compatibility wrappers: **1**
- Feature groups: **10** (career, daily, duel, economy, game, home, notifications, settings, social, tutorial)
- Required device behavior: compact phone, large phone/tablet, text scaling, safe insets, keyboard insets and scroll recovery
- Required state behavior: loading, empty, recoverable error, disabled/busy and completed/outcome
- Required message behavior: no raw exception, HTTP code, Firebase/backend/OAuth/SHA/configuration text in production UI

## High-impact findings fixed

1. **Sudoku cell visibility:** selected user values now use a white high-contrast foreground and shadow; selected, related, matching, fixed, hinted and error states have distinct colors.
2. **Pause flow:** explicit pause button, stopped timer, hidden board, disabled controls, continue/restart/main-menu actions, restart confirmation and back-button interception.
3. **16×16 Fantasy:** valid unique 4×4-box puzzle, 1–9/A–G symbols, responsive number grid, zoom/pan, persistence and a visible main-experience launcher.
4. **Google Play identity:** live player name/avatar refresh, first-profile creation and protection of a confirmed custom nickname.
5. **Profile hierarchy:** identity header, platform status, ELO/rank/peak/country, W-L-D/win rate/streak/tournament data, achievements and separate account/social actions.
6. **Technical error exposure:** central `UserSafeError`, static CI guard and user-safe network/account/server messages across online, social, wallet, settings and platform flows.
7. **Shared feedback system:** `UxStatePanel`, `UxMetricTile`, `UxOutcomeHeader` and `UxOutcomeSheet` now define loading/empty/error/result presentation.
8. **Outcome consistency:** career/practice/daily completion, loss/continue, local duel and online duel share the same outcome header and information hierarchy.
9. **Gameplay route consistency:** career and daily modes now open `EnhancedGameScreen`; compatibility wrappers are reported separately instead of being treated as broken screens.
10. **Release safety:** localization, user-safe messages, UX contracts, fatal analyzer, tests, debug APK and release AAB are CI gates.

## Screen inventory

| Feature | Screen / file | Role | Safe area | Responsive | Scroll | State feedback | Safe errors | Shared state | Shared outcome | Localized | Static finding |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| career | `CareerHubScreen`<br>`lib/features/career/career_hub_screen.dart` | Production screen | Yes | Yes | Yes | Yes | — | — | Yes | Yes | Remote failure path needs user-safe mapping review |
| career | `CareerScreen`<br>`lib/features/career/career_screen.dart` | Production screen | Yes | Yes | Yes | Yes | — | — | Yes | Yes | Remote failure path needs user-safe mapping review |
| daily | `DailyScreen`<br>`lib/features/daily/daily_screen.dart` | Production screen | — | — | — | — | Yes | — | Yes | Yes | No explicit responsive primitive detected |
| duel | `DuelScreen`<br>`lib/features/duel/duel_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| duel | `LeaderboardsScreen`<br>`lib/features/duel/leaderboards_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| duel | `MatchmakingScreen`<br>`lib/features/duel/matchmaking_screen.dart` | Production screen | Yes | Yes | — | — | Yes | — | Yes | Yes | Dense column without explicit scroll marker |
| duel | `OnlineDuelScreen`<br>`lib/features/duel/online_duel_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | — | Yes | Outcome content does not use shared outcome component |
| duel | `PreMatchReadyScreen`<br>`lib/features/duel/pre_match_ready_screen.dart` | Production screen | Yes | Yes | — | Yes | Yes | — | Yes | Yes | Dense column without explicit scroll marker |
| duel | `RankedProgressScreen`<br>`lib/features/duel/ranked_progress_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| economy | `CoinStoreScreen`<br>`lib/features/economy/coin_store_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| economy | `WalletHistoryScreen`<br>`lib/features/economy/wallet_history_screen.dart` | Production screen | Yes | Yes | — | Yes | Yes | Yes | Yes | Yes | Dense column without explicit scroll marker |
| game | `EnhancedGameScreen`<br>`lib/features/game/enhanced_game_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | — | Yes | Outcome content does not use shared outcome component |
| game | `GameScreen`<br>`lib/features/game/game_screen.dart` | Production screen | Yes | Yes | — | Yes | Yes | — | — | Yes | Dense column without explicit scroll marker; Outcome content does not use shared outcome component |
| game | `SamuraiGameScreen`<br>`lib/features/game/samurai_game_screen.dart` | Production screen | Yes | — | — | — | Yes | — | Yes | Yes | No explicit responsive primitive detected |
| home | `HomeScreen`<br>`lib/features/home/home_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| home | `ProfessionalHomeScreen`<br>`lib/features/home/professional_home_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| home | `UxRootScreen`<br>`lib/features/home/ux_root_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| notifications | `DailyReminderDestinationScreen`<br>`lib/features/notifications/daily_reminder_destination_screen.dart` | Production screen | Yes | — | — | Yes | — | — | Yes | Yes | Remote failure path needs user-safe mapping review; No explicit responsive primitive detected |
| settings | `UxSettingsScreen`<br>`lib/features/settings/ux_settings_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `ChallengeInvitationScreen`<br>`lib/features/social/challenge_invitation_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `ChallengeWaitingScreen`<br>`lib/features/social/challenge_waiting_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `EmoteLoadoutScreen`<br>`lib/features/social/emote_loadout_screen.dart` | Production screen | Yes | Yes | Yes | — | Yes | — | Yes | Yes | No static warning |
| social | `FriendRequestsScreen`<br>`lib/features/social/friend_requests_screen.dart` | Production screen | — | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No static warning |
| social | `GooglePlayGamesScreen`<br>`lib/features/social/google_play_games_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `PlatformServicesScreen`<br>`lib/features/social/platform_services_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `PlatformSocialScreen`<br>`lib/features/social/platform_social_screen.dart` | Production screen | — | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `PlayerProfileScreen`<br>`lib/features/social/player_profile_screen.dart` | Forwarding wrapper | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | No static warning |
| social | `ProfileCustomizationScreen`<br>`lib/features/social/profile_customization_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `ProfileHubScreen`<br>`lib/features/social/profile_hub_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `RematchInvitationScreen`<br>`lib/features/social/rematch_invitation_screen.dart` | Production screen | Yes | Yes | — | Yes | Yes | — | Yes | Yes | Dense column without explicit scroll marker |
| social | `SocialHubScreen`<br>`lib/features/social/social_hub_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| social | `UxChallengeInvitationScreen`<br>`lib/features/social/ux_challenge_invitation_screen.dart` | Production screen | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | No static warning |
| tutorial | `TutorialScreen`<br>`lib/features/tutorial/tutorial_screen.dart` | Production screen | Yes | Yes | — | — | Yes | — | Yes | Yes | Dense column without explicit scroll marker |

## Static warnings requiring visual regression attention

- `lib/features/career/career_hub_screen.dart`: Remote failure path needs user-safe mapping review
- `lib/features/career/career_screen.dart`: Remote failure path needs user-safe mapping review
- `lib/features/daily/daily_screen.dart`: No explicit responsive primitive detected
- `lib/features/duel/matchmaking_screen.dart`: Dense column without explicit scroll marker
- `lib/features/duel/online_duel_screen.dart`: Outcome content does not use shared outcome component
- `lib/features/duel/pre_match_ready_screen.dart`: Dense column without explicit scroll marker
- `lib/features/economy/wallet_history_screen.dart`: Dense column without explicit scroll marker
- `lib/features/game/enhanced_game_screen.dart`: Outcome content does not use shared outcome component
- `lib/features/game/game_screen.dart`: Dense column without explicit scroll marker; Outcome content does not use shared outcome component
- `lib/features/game/samurai_game_screen.dart`: No explicit responsive primitive detected
- `lib/features/notifications/daily_reminder_destination_screen.dart`: Remote failure path needs user-safe mapping review; No explicit responsive primitive detected
- `lib/features/social/rematch_invitation_screen.dart`: Dense column without explicit scroll marker
- `lib/features/tutorial/tutorial_screen.dart`: Dense column without explicit scroll marker

Static warnings are not automatically defects. Confirmation dialogs, short setup screens and game canvases may intentionally omit a list or common state panel. They remain listed so visual/device tests do not silently skip them.

## Interaction and accessibility rules

- Primary controls use at least 44–48 logical pixels and remain reachable under text scaling.
- Destructive restart/account actions require confirmation.
- Long and data-driven screens use scrollable content and refresh/retry recovery.
- Result sheets expose a single primary action, optional secondary action and lower-emphasis exit action.
- Loading and error regions use semantic live regions; Sudoku cells expose row, column, value and selected state.
- Platform identity is advisory: it may initialize a profile but cannot overwrite a confirmed custom nickname.
- 16×16 is offline/special mode and does not silently affect online rating or career progression.

## Verification gates

- `python3 tool/validate_localizations.py`
- `python3 tool/verify_user_facing_messages.py`
- `python3 tool/verify_ux_contracts.py`
- `python3 tool/generate_ux_audit.py --check`
- `flutter analyze --fatal-infos`
- `flutter test --concurrency=1`
- `flutter build apk --debug`
- `flutter build appbundle --release`
- `tool/verify_android_release_config.ps1`
- `tool/verify_online_aab.ps1`

## Manual release smoke matrix

1. Install from Google Play internal testing, not by sideloading the local APK.
2. Confirm Play Games consent, automatic avatar/name and preserved custom nickname.
3. Enter a number into a selected cell in normal and high-contrast modes.
4. Pause for at least ten seconds; confirm time does not advance and the board is hidden.
5. Restart and return to menu; confirm save/confirmation behavior.
6. Open 16×16, enter A–G values, add notes, zoom, background the app and resume.
7. Exercise offline/server-down states for profile, friends, leaderboard, wallet and matchmaking; verify no technical text appears.
8. Complete and lose career/practice/daily/local duel/online duel sessions; compare visual hierarchy and action order.
9. Test 320×568, 360×800, 412×915 and tablet widths with text scale 1.0, 1.3 and 2.0.
