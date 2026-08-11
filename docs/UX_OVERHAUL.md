# Unified UX architecture

The primary app route now uses a coordinated UX root instead of independent startup gates.

## Principles

- Online identity is requested only when an online or social feature needs it.
- Challenge and rematch deep links are routed sequentially.
- Challenge affordability is calculated from the selected difficulty fee.
- Career, practice and daily games persist the complete puzzle definition.
- Resume content is part of the home scroll hierarchy, never a floating overlay.
- Career renders one ten-level chapter at a time.
- Daily rewards are visible from Home and the Coin Store.
- Coin spending in the primary gameplay flow uses the server wallet.
- The app presents one intentional dark visual system with optional high contrast.

## Primary screens

- `UxRootScreen`
- `CareerHubScreen`
- `EnhancedGameScreen`
- `SocialHubScreen`
- `ProfileHubScreen`
- `UxSettingsScreen`
- `UxChallengeInvitationScreen`
