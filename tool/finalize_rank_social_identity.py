#!/usr/bin/env python3
from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, path: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f'{path}: expected exactly one occurrence, found {count}: {old[:120]!r}'
        )
    return text.replace(old, new, 1)


# The social backend already returns players.avatar_key. Preserve it in the
# client model so rank frames and equipped achievement decorations travel
# through existing friends/challenge payloads without a new protocol.
path = 'lib/services/social_api_client.dart'
s = read(path)
s = replace_once(
    s,
    "    required this.displayName,\n    required this.rating,\n",
    "    required this.displayName,\n    this.avatarKey = 'default',\n    required this.rating,\n",
    path,
)
s = replace_once(
    s,
    "  final String displayName;\n  final int rating;\n",
    "  final String displayName;\n  final String avatarKey;\n  final int rating;\n",
    path,
)
s = replace_once(
    s,
    "      displayName: json['displayName']?.toString() ?? 'Player',\n      rating: (json['rating'] as num?)?.toInt() ?? 1000,\n",
    "      displayName: json['displayName']?.toString() ?? 'Player',\n      avatarKey: json['avatarKey']?.toString() ?? 'default',\n      rating: (json['rating'] as num?)?.toInt() ?? 1000,\n",
    path,
)
write(path, s)

# Friends/search/recent-opponent cards now render the server-backed identity
# key instead of synthetic local-only keys.
path = 'lib/features/social/social_hub_screen.dart'
s = read(path)
s = replace_once(
    s,
    "              avatarKey: 'social-${challenge.challenger.publicId}',\n",
    '              avatarKey: challenge.challenger.avatarKey,\n',
    path,
)
s = replace_once(
    s,
    "              avatarKey: 'player-${player.publicId}',\n",
    '              avatarKey: player.avatarKey,\n',
    path,
)
write(path, s)

path = 'lib/features/social/friend_requests_screen.dart'
s = read(path)
s = replace_once(
    s,
    "import '../../widgets/in_page_header.dart';\n",
    "import '../../widgets/in_page_header.dart';\nimport '../../widgets/player_avatar.dart';\n",
    path,
)
s = replace_once(
    s,
    "                                leading: const CircleAvatar(\n                                  child: Icon(Icons.person_add_alt_1_outlined),\n                                ),\n",
    "                                leading: PlayerAvatar(\n                                  displayName: player.displayName,\n                                  avatarKey: player.avatarKey,\n                                  radius: 24,\n                                ),\n",
    path,
)
write(path, s)

path = 'lib/features/social/challenge_invitation_screen.dart'
s = read(path)
s = replace_once(
    s,
    "                  avatarKey: 'challenge-${challenge.challenger.publicId}',\n",
    '                  avatarKey: challenge.challenger.avatarKey,\n',
    path,
)
write(path, s)

# This is the challenge invitation reached by the current social hub. It must
# not display hidden Elo and it must show the challenger's equipped identity.
path = 'lib/features/social/ux_challenge_invitation_screen.dart'
s = read(path)
s = replace_once(
    s,
    "                  avatarKey: 'challenge-${challenge.challenger.publicId}',\n",
    '                  avatarKey: challenge.challenger.avatarKey,\n',
    path,
)
s = replace_once(
    s,
    "                    _Metric(\n                      asset: DuelAsset.trophy,\n                      label: context.tr('rating_value', <Object>[\n                        challenge.challenger.rating,\n                      ]),\n                      color: const Color(0xFFFFC94D),\n                    ),\n",
    "                    _Metric(\n                      asset: DuelAsset.trophy,\n                      label: context.tr('games_count', <Object>[\n                        challenge.challenger.gamesPlayed,\n                      ]),\n                      color: const Color(0xFFFFC94D),\n                    ),\n",
    path,
)
write(path, s)

# The sender's waiting screen is part of the same challenge flow. Preserve the
# recipient identity here too and remove the last legacy Elo label.
path = 'lib/features/social/challenge_waiting_screen.dart'
s = read(path)
s = replace_once(
    s,
    "                            avatarKey: 'challenge-wait-${recipient.publicId}',\n",
    '                            avatarKey: recipient.avatarKey,\n',
    path,
)
s = replace_once(
    s,
    "                              _InfoChip(\n                                asset: DuelAsset.trophy,\n                                label: context.tr('rating_value', <Object>[\n                                  recipient.rating,\n                                ]),\n                                accent: const Color(0xFFFFC94D),\n                              ),\n",
    "                              _InfoChip(\n                                asset: DuelAsset.trophy,\n                                label: context.tr('games_count', <Object>[\n                                  recipient.gamesPlayed,\n                                ]),\n                                accent: const Color(0xFFFFC94D),\n                              ),\n",
    path,
)
write(path, s)

# Platform-social keeps its native/platform controls unchanged. Sudoku Duel
# player rows use decorated avatars and activity stats rather than hidden MMR.
path = 'lib/features/social/platform_social_screen.dart'
s = read(path)
if "import '../../widgets/player_avatar.dart';\n" not in s:
    s = replace_once(
        s,
        "import '../../widgets/in_page_header.dart';\n",
        "import '../../widgets/in_page_header.dart';\nimport '../../widgets/player_avatar.dart';\n",
        path,
    )
s = replace_once(
    s,
    "                        const CircleAvatar(child: Icon(Icons.person_outline)),\n",
    "                        PlayerAvatar(\n                          displayName: player.displayName,\n                          avatarKey: player.avatarKey,\n                          radius: 20,\n                        ),\n",
    path,
)
s = replace_once(
    s,
    "                              Text(\n                                context\n                                    .tr('player_rating_wins_summary', <Object>[\n                                      player.username,\n                                      player.rating,\n                                      player.wins,\n                                      player.gamesPlayed,\n                                    ]),\n                              ),\n",
    "                              Text(\n                                '@${player.username} · ${context.tr('games_count', <Object>[player.gamesPlayed])} · ${context.tr('wins_count', <Object>[player.wins])}',\n                              ),\n",
    path,
)
write(path, s)

# Extend the public-surface contract guard from the previous integration pass
# without introducing duplicate map keys.
path = 'test/rank_identity_public_ui_contract_test.dart'
s = read(path)
s = replace_once(
    s,
    "      'lib/features/social/platform_social_screen.dart': <String>[\n        'currentElo',\n        '_competitiveProfile',\n        'CompetitiveProfileCard',\n      ],\n",
    "      'lib/features/social/platform_social_screen.dart': <String>[\n        'currentElo',\n        '_competitiveProfile',\n        'CompetitiveProfileCard',\n        'player.rating,',\n      ],\n",
    path,
)
s = replace_once(
    s,
    "      'lib/features/social/challenge_invitation_screen.dart': <String>[\n        \"value: '${challenge.challenger.rating}'\",\n      ],\n",
    "      'lib/features/social/challenge_invitation_screen.dart': <String>[\n        \"value: '${challenge.challenger.rating}'\",\n      ],\n      'lib/features/social/ux_challenge_invitation_screen.dart': <String>[\n        'challenge.challenger.rating',\n      ],\n      'lib/features/social/challenge_waiting_screen.dart': <String>[\n        'recipient.rating',\n      ],\n",
    path,
)
write(path, s)

# Model contract: existing social payloads carry the decorated identity key.
Path('test/social_player_identity_model_test.dart').write_text(
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_game/services/social_api_client.dart';

void main() {
  test('SocialPlayer preserves the backend avatar identity key', () {
    final player = SocialPlayer.fromJson(<String, dynamic>{
      'publicId': 'PLAYER1',
      'username': 'logic_player',
      'displayName': 'Logic Player',
      'avatarKey': 'idv1|preset_007|gold_2|unbeaten_shield_50,perfect_star',
      'rating': 1732,
      'gamesPlayed': 80,
      'wins': 51,
      'achievementCount': 8,
    });

    expect(
      player.avatarKey,
      'idv1|preset_007|gold_2|unbeaten_shield_50,perfect_star',
    );
    // Legacy rating still exists internally for backend compatibility; public
    // widgets are guarded separately from rendering it.
    expect(player.rating, 1732);
  });
}
''',
    encoding='utf-8',
)
