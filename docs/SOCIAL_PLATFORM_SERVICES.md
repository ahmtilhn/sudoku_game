# Social, Friends, Challenges, and Platform Game Services

This document defines the supported architecture for Sudoku Duel social features. It is based on the current Google Play Games Services and Apple Game Center documentation as reviewed on 2026-07-24.

## Product goal

The social screen must stay challenge-first and simple:

1. Quick match by Sudoku difficulty.
2. Friends and recent opponents.
3. Search a Sudoku Duel username.
4. Open a compact player card.
5. The primary action is **Challenge**.
6. Secondary information is rank, wins, recent form, and achievement summary.

## Important platform limitation

Google Play Games and Apple Game Center are separate identity networks. A Google Play player ID cannot identify the same person on Apple, and a Game Center player ID cannot identify the same person on Android.

The platform services are useful for:

- platform authentication;
- importing platform friends after consent;
- opening the native player profile;
- submitting and reading leaderboards;
- reporting and showing achievements;
- Apple Game Center invitations and matchmaking.

They cannot be the only database for a cross-platform Sudoku Duel friend and challenge system.

A small shared backend is required for:

- global Sudoku Duel username search;
- Android-to-iOS friendships;
- friend requests and blocks;
- challenges and challenge state;
- recent opponents;
- authoritative match state;
- public cross-platform statistics.

## Google Play Games Services

Use Play Games Services v2 only.

Supported:

- automatic platform authentication;
- stable player identity verified by a backend using a one-time server auth code;
- consent-based loading of Play Games friends;
- native compare-profile UI, including Play Games friendship controls;
- social and global leaderboards;
- achievements for the authenticated player;
- Game Stats events and progression statistics.

Not supported:

- Google Play Games real-time multiplayer;
- Google Play Games turn-based multiplayer;
- arbitrary global player search by Gamer ID inside the app;
- treating a device-supplied player ID as trusted backend identity;
- reading every remote player's private achievement progress.

Google ended the Play Games multiplayer APIs on 2020-03-31. Android matches therefore need the shared Sudoku Duel backend.

Official references:

- https://developer.android.com/games/pgs/android/android-signin
- https://developer.android.com/games/pgs/android/server-access
- https://developer.android.com/games/pgs/android/friends
- https://developer.android.com/games/pgs/android/leaderboards
- https://developer.android.com/games/pgs/android/achievements
- https://developer.android.com/games/pgs/gamestats
- https://support.google.com/googleplay/android-developer/answer/9875345

## Apple Game Center

Supported:

- Game Center authentication;
- privacy-scoped `gamePlayerID` identity;
- consent-based friend loading;
- recent-player loading;
- native friend request creator;
- native player profile UI;
- friends-only and global leaderboards;
- achievements for the authenticated player;
- real-time and turn-based matchmaking and friend invitations.

Privacy rules:

- request friend-list permission only when the player opens social features;
- add `NSGKFriendListUsageDescription` before requesting permission;
- store `gamePlayerID`, not mutable display names or deprecated `playerID`;
- verify the local Game Center player with Apple's identity verification signature before linking it to a backend account;
- only friends who also grant access are returned by `loadFriends()`.

Official references:

- https://developer.apple.com/documentation/gamekit/authenticating-a-player
- https://developer.apple.com/documentation/gamekit/connecting-players-with-their-friends-in-your-game
- https://developer.apple.com/documentation/gamekit/protecting-the-player-s-privacy-using-scoped-identifiers
- https://developer.apple.com/documentation/gamekit/creating-real-time-games
- https://developer.apple.com/documentation/gamekit/creating-turn-based-games
- https://developer.apple.com/documentation/gamekit/encourage-progress-and-competition-with-leaderboards
- https://developer.apple.com/documentation/gamekit/rewarding-players-with-achievements

## What appears on another player's compact profile

Use a merged model, not raw platform data.

Always available from the Sudoku Duel backend:

- public username;
- avatar preset;
- games played;
- wins, losses, and win rate;
- current rating;
- global cross-platform rank;
- best difficulty reached;
- public achievement count;
- last played timestamp;
- friendship and challenge state.

Optional platform badges:

- Google Play Games linked;
- Apple Game Center linked;
- platform leaderboard rank where the platform API returns that player;
- a button that opens the native platform profile.

Do not promise a remote player's complete achievement list. Both stores primarily expose achievement progress for the authenticated player. Public achievement summaries must therefore be mirrored from server-validated game events into the Sudoku Duel profile.

## Search behavior

The search box searches a normalized Sudoku Duel username in the shared directory.

It does not search all Google Play Gamer IDs or all Game Center aliases because neither platform provides a general arbitrary-player search API suitable for this UI.

Platform friends are imported separately after consent and linked to matching Sudoku Duel accounts by verified platform identifiers.

## Friends and recent opponents

Sources are merged and deduplicated:

1. Sudoku Duel accepted friends.
2. Imported Google Play friends who also use Sudoku Duel.
3. Imported Game Center friends who also use Sudoku Duel.
4. Recent opponents stored after a completed or accepted match.

A recent opponent remains challengeable without forcing a friendship. The player can optionally add them as a Sudoku Duel friend.

## Challenge flow

1. Challenger selects a player.
2. Challenger selects difficulty.
3. Backend creates a challenge with an expiry time and one-time challenge ID.
4. Recipient receives the pending challenge in the app and, later, a push notification.
5. Recipient accepts or declines.
6. On acceptance, the backend creates one authoritative game room and one shared puzzle seed.
7. Both clients receive the same public puzzle state; the complete solution remains authoritative on the server.
8. Results update cross-platform statistics and submit eligible local-player results to the current platform leaderboard/achievement service.

## Recommended no-cost backend

Use Cloudflare Workers Free with:

- D1 for player directory, friendships, challenges, recent opponents, public stats, and blocks;
- SQLite-backed Durable Objects for matchmaking queues and authoritative live game rooms;
- WebSocket hibernation for connected matches;
- scheduled cleanup implemented without paid-only TTL features.

Current free-plan limits are suitable for an MVP:

- D1: 5 million rows read/day, 100,000 rows written/day, and 5 GB total included storage;
- Durable Objects: 100,000 requests/day and 13,000 GB-s/day;
- exceeding a Free-plan daily limit causes operations to fail rather than silently creating usage charges.

This is a no-cost starting architecture, not an unlimited-cost guarantee. Usage dashboards and hard application rate limits are still required.

Official references:

- https://developers.cloudflare.com/d1/platform/pricing/
- https://developers.cloudflare.com/durable-objects/platform/pricing/
- https://developers.cloudflare.com/durable-objects/platform/limits/

## Backend data model

### `players`

- `id`: internal random UUID;
- `public_id`: shareable short ID;
- `username_normalized`: unique search key;
- `display_name`;
- `avatar_key`;
- `google_player_id_hash` nullable;
- `apple_game_player_id_hash` nullable;
- `rating`;
- `games_played`;
- `wins`;
- `losses`;
- `achievement_count`;
- `created_at`;
- `last_seen_at`.

Raw platform identifiers should be encrypted or one-way indexed where possible. They are never displayed.

### `friendships`

- ordered pair of player IDs;
- status: `pending`, `accepted`, `declined`, `blocked`;
- requester ID;
- created and updated timestamps.

### `challenges`

- challenge ID;
- challenger and recipient IDs;
- selected difficulty;
- status: `pending`, `accepted`, `declined`, `expired`, `cancelled`, `completed`;
- expiry timestamp;
- game-room ID nullable.

### `recent_opponents`

- ordered pair of player IDs;
- last match ID;
- last result;
- last played timestamp.

### `public_achievements`

- player ID;
- internal achievement ID;
- progress;
- unlocked timestamp.

## Security requirements

- verify Google server auth codes on the backend before linking a Play Games identity;
- verify Apple Game Center identity signatures before linking a Game Center identity;
- never trust client-submitted wins, rating, ranks, currency, hints, or match outcomes;
- use one-time idempotency keys for challenge acceptance and match completion;
- rate-limit username search, friend requests, and challenges;
- support blocking and prevent blocked users from searching/challenging each other;
- avoid free-text chat in the first release to reduce moderation and child-safety scope;
- do not expose email addresses, platform IDs, IP addresses, or exact last-online presence;
- let users revoke imported-friend access and unlink a platform identity;
- document the stored platform identifiers and social graph in store privacy disclosures.

## Current repository readiness

The current project is not yet ready to authenticate with either platform:

- Android application ID is still `com.example.sudoku_game`;
- no Play Games Services v2 dependency is configured;
- no Play Games project ID or game-server OAuth client is configured;
- iOS has no Game Center entitlement;
- iOS `Info.plist` has no `NSGKFriendListUsageDescription`;
- no platform social MethodChannel exists;
- no shared backend URL or authentication flow exists.

These values must be configured before native friend/leaderboard calls are enabled.

## Implementation order

### Phase 1 — identity and platform bridge

- finalize Android application ID and iOS bundle ID;
- create one Play Games project and configure PGS v2 credentials;
- enable Game Center and create the entitlement;
- implement native authentication bridges;
- verify both identities on the backend;
- create/link a Sudoku Duel account.

### Phase 2 — simple social screen

- Friends;
- Recent opponents;
- username search;
- compact profile;
- primary Challenge action;
- add/remove/block friend;
- native platform-profile button.

### Phase 3 — authoritative challenges and matches

- difficulty-specific challenge;
- accept/decline/expiry;
- Durable Object room;
- reconnect and forfeiture handling;
- server-validated results;
- recent-opponent update.

### Phase 4 — store statistics

- configure matching leaderboard and achievement IDs in both stores;
- submit equivalent game events to both stores;
- load the authenticated player's platform progress;
- load friend/global leaderboard entries where available;
- mirror only server-validated public summaries into the cross-platform profile.

## UI rule

The compact player card must not become a statistics dashboard. Show at most:

- username and avatar;
- friend/recent/platform badges;
- rating and global rank;
- wins and games played;
- achievement count;
- one dominant **Challenge** button;
- one overflow menu for add friend, remove friend, block, and native platform profile.
