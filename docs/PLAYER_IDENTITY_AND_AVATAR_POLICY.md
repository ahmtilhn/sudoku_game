# Player Identity and Avatar Policy

This document separates permanent Sudoku Duel identity from platform identity and avatar presentation. It is a design lock for future competitive work.

## Identity Sources

| Identity | Owner | Stability | Use |
|---|---|---|---|
| Firebase UID | Firebase Auth | Primary account key; changes only when the player signs into a different Firebase account | Backend account lookup and deletion/tombstone policy. |
| `publicId` | Sudoku Duel backend | Permanent public Friend ID | Friend search, support-safe player reference, challenge targeting. |
| `username` | Sudoku Duel backend | Unique game name; editable under validation | Search/display identity, not account ownership. |
| Display name | Sudoku Duel backend | Editable | UI display; never an ownership key. |
| Game Center `gamePlayerID` | Apple/Game Center | Scoped platform id | Optional verified platform binding; not the Sudoku Duel account key. |
| Google Play Games game-scoped player ID | Google Play Games | Scoped platform id | Optional verified platform binding; not the Sudoku Duel account key. |
| Platform display name/avatar | Apple/Google | May change externally | UI hint only unless explicitly synced with consent. |

## Current Implementation Audit

- `players.firebase_uid` exists and is unique.
- `players.public_id`, `username`, `username_normalized`, `display_name`, `avatar_key` exist.
- `players.google_player_id_hash` and `players.apple_player_id_hash` exist, but no complete verified mapping route/lifecycle is implemented.
- Flutter `PlatformGameServices` can read platform player id, display name, alias and avatar URL through a method channel.
- Player profile creation may use a platform display name as a suggestion/name source.
- The backend strips client-provided `/v1/me` display name during auto profile creation and validates profile preference updates.

## Locked Rules

- Firebase UID remains the primary account identity.
- `publicId` remains the player-facing permanent Friend ID.
- `username` remains the unique game name. It is not a login credential and not a platform identity.
- Platform ids may be linked only after provider-specific verification.
- Platform names and avatars are not durable account identifiers.
- If the platform account changes, the Sudoku Duel account remains the same Firebase UID/player row until the player explicitly links or unlinks a verified platform binding.
- If a new platform id is verified for an existing Firebase UID, store it as a new binding event and require conflict checks against other player rows.
- If a platform id is already bound to another player, reject the link and require account recovery/support flow.

## Avatar Model Design

Future migration `0017_player_identity_avatar_sources.sql` should add these fields or a separate avatar table:

| Field | Type | Meaning |
|---|---|---|
| `avatarKey` | text | Existing preset or local display key. |
| `avatarSource` | enum text | `preset`, `google_play_games`, `game_center_local`, `synced_custom`. |
| `avatarVersion` | integer | Monotonic version for cache busting and conflict resolution. |
| `platformAvatarUpdatedAt` | text nullable | Last observed platform avatar timestamp, if known. |
| `syncedAvatarUrl` | text nullable | Backend-owned synced image URL, if explicitly enabled. |
| `avatarConsentVersion` | text nullable | Consent/policy version accepted before sync. |

Allowed `avatarSource` values:

- `preset`: built-in game avatar key; default and safest current behavior.
- `google_play_games`: local platform avatar presentation from Google Play Games.
- `game_center_local`: local Game Center avatar presentation on device only.
- `synced_custom`: backend-hosted image after explicit consent and moderation/storage rules.

## Game Center Photo Policy

Do not automatically upload Game Center photos to the backend.

A future `syncedPlatformAvatars` feature flag may allow explicit opt-in sync only after:

- user consent is shown and versioned;
- storage, retention and deletion behavior is documented;
- image moderation/security constraints are implemented;
- account deletion removes or anonymizes synced avatar data according to policy.

## Platform Account Change Behavior

| Scenario | Behavior |
|---|---|
| Same Firebase UID, same platform id | Continue normally; refresh non-authoritative display hints. |
| Same Firebase UID, different platform id | Treat as platform relink candidate; do not move wallet/rating automatically. |
| Different Firebase UID, same platform id | Reject automatic link; require recovery/support policy. |
| Platform name changes | Allow display suggestion only; do not rename game profile automatically. |
| Platform avatar changes | Update local UI hint only unless `syncedPlatformAvatars` is enabled and consented. |

## API Draft

`GET /v1/competitive/profile` should return:

- `publicId`, `username`, `displayName`;
- `avatarKey`, `avatarSource`, `avatarVersion`;
- platform binding state without exposing raw platform ids;
- enabled competitive feature flags;
- country profile state when country features are enabled.

Raw platform ids should never be returned to other players.
