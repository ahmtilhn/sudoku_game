#!/usr/bin/env python3
from pathlib import Path
import re


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


# Matchmaking presentation: visible RP only. The queue and backend MMR are not
# touched by this script.
path = 'lib/features/duel/matchmaking_stage.dart'
s = read(path)
s = replace_once(s, '    this.rating,\n', '    this.rankPoints,\n', path)
s = replace_once(s, '  final int? rating;\n', '  final int? rankPoints;\n', path)
s = replace_once(s, '    int? rating,\n', '    int? rankPoints,\n', path)
s = replace_once(
    s,
    '      rating: rating ?? this.rating,\n',
    '      rankPoints: rankPoints ?? this.rankPoints,\n',
    path,
)
s = replace_once(
    s,
    "            value: player.rating?.toString() ?? '—',\n"
    "            label: context.tr('rating'),\n",
    "            value: player.rankPoints?.toString() ?? '—',\n"
    "            label: 'RP',\n",
    path,
)
s = replace_once(
    s,
    "        Expanded(child: _Stat(value: '—', label: context.tr('rating'))),\n",
    "        const Expanded(child: _Stat(value: '—', label: 'RP')),\n",
    path,
)
if re.search(r'\brating\b', s):
    raise SystemExit(f'{path}: stale presentation rating identifier remains')
write(path, s)

path = 'lib/features/duel/matchmaking_screen.dart'
s = read(path)
s = replace_once(
    s,
    "import '../../services/firebase_session_service.dart';\n",
    "import '../../services/firebase_session_service.dart';\n"
    "import '../../services/platform_game_services.dart';\n",
    path,
)
s = replace_once(
    s,
    "    return MatchmakingVisualPlayer(\n"
    "      displayName: profile.displayName,\n"
    "      avatarKey: profile.avatarKey,\n"
    "      rankLabel: profile.rankName,\n"
    "      gamesPlayed: stats.rankedGames,\n"
    "      winRate: winRate,\n"
    "      // Legacy presentation slot: visible RP only, never matchmaking MMR.\n"
    "      rating: profile.rankPoints,\n"
    "    );\n",
    "    final platform = PlatformGameServices.instance.localPlayer.value;\n"
    "    final baseAvatarKey = RankIdentityKey.parse(profile.avatarKey).avatarKey;\n"
    "    return MatchmakingVisualPlayer(\n"
    "      displayName: profile.displayName,\n"
    "      avatarKey: profile.avatarKey,\n"
    "      remoteApprovedImageUrl: baseAvatarKey.startsWith('home-profile-')\n"
    "          ? platform?.avatarUrl\n"
    "          : null,\n"
    "      rankLabel: profile.rankName,\n"
    "      gamesPlayed: stats.rankedGames,\n"
    "      winRate: winRate,\n"
    "      rankPoints: profile.rankPoints,\n"
    "    );\n",
    path,
)
write(path, s)

path = 'lib/features/duel/pre_match_ready_screen.dart'
s = read(path)
s = replace_once(
    s,
    "import '../../services/online_duel_transport.dart';\n",
    "import '../../services/online_duel_transport.dart';\n"
    "import '../../models/rank_identity_models.dart';\n"
    "import '../../services/platform_game_services.dart';\n",
    path,
)
s = replace_once(
    s,
    "      setState(() {\n"
    "        _profilePlayer = MatchmakingVisualPlayer(\n"
    "          displayName: profile.displayName,\n"
    "          avatarKey: profile.avatarKey,\n"
    "          rankLabel: profile.rankName,\n"
    "          gamesPlayed: stats.rankedGames,\n"
    "          winRate: winRate,\n"
    "          // Legacy presentation slot, now populated with visible RP only.\n"
    "          rating: profile.rankPoints,\n"
    "        );\n"
    "      });\n",
    "      final platform = PlatformGameServices.instance.localPlayer.value;\n"
    "      final baseAvatarKey = RankIdentityKey.parse(profile.avatarKey).avatarKey;\n"
    "      setState(() {\n"
    "        _profilePlayer = MatchmakingVisualPlayer(\n"
    "          displayName: profile.displayName,\n"
    "          avatarKey: profile.avatarKey,\n"
    "          remoteApprovedImageUrl: baseAvatarKey.startsWith('home-profile-')\n"
    "              ? platform?.avatarUrl\n"
    "              : null,\n"
    "          rankLabel: profile.rankName,\n"
    "          gamesPlayed: stats.rankedGames,\n"
    "          winRate: winRate,\n"
    "          rankPoints: profile.rankPoints,\n"
    "        );\n"
    "      });\n",
    path,
)
s = replace_once(s, '      rating: base?.rating,\n', '      rankPoints: base?.rankPoints,\n', path)
s = replace_once(
    s,
    '      rating: profileMatches ? publicProfile.rankPoints : null,\n',
    '      rankPoints: profileMatches ? publicProfile.rankPoints : null,\n',
    path,
)
write(path, s)

# Remove hidden MMR from social/challenge presentation while leaving all social
# API payloads and challenge mechanics intact.
path = 'lib/features/social/social_hub_screen.dart'
s = read(path)
s = replace_once(
    s,
    "              '${context.strings.difficultyLabel(_difficulty(challenge.difficulty))} · "
    "${context.tr('rating_value', <Object>[challenge.challenger.rating])}',\n",
    "              '${context.strings.difficultyLabel(_difficulty(challenge.difficulty))} · "
    "${context.tr('games_count', <Object>[challenge.challenger.gamesPlayed])}',\n",
    path,
)
s = replace_once(
    s,
    "                  Text(\n"
    "                    context.tr('player_rating_summary', <Object>[\n"
    "                      player.username,\n"
    "                      player.rating,\n"
    "                    ]),\n"
    "                    maxLines: 1,\n"
    "                    overflow: TextOverflow.ellipsis,\n"
    "                  ),\n",
    "                  Text(\n"
    "                    '@${player.username} · ${context.tr('games_count', <Object>[player.gamesPlayed])}',\n"
    "                    maxLines: 1,\n"
    "                    overflow: TextOverflow.ellipsis,\n"
    "                  ),\n",
    path,
)
write(path, s)

path = 'lib/features/social/friend_requests_screen.dart'
s = read(path)
s = replace_once(
    s,
    "                                subtitle: Text(\n"
    "                                  context.tr('player_rating_summary', <Object>[\n"
    "                                    player.username,\n"
    "                                    player.rating,\n"
    "                                  ]),\n"
    "                                ),\n",
    "                                subtitle: Text(\n"
    "                                  '@${player.username} · ${context.tr('games_count', <Object>[player.gamesPlayed])}',\n"
    "                                ),\n",
    path,
)
write(path, s)

path = 'lib/features/social/challenge_invitation_screen.dart'
s = read(path)
s = replace_once(
    s,
    "                    child: _Metric(\n"
    "                      asset: DuelAsset.trophy,\n"
    "                      label: context.tr('rating'),\n"
    "                      value: '${challenge.challenger.rating}',\n"
    "                      color: const Color(0xFFFFC94D),\n"
    "                    ),\n",
    "                    child: _Metric(\n"
    "                      asset: DuelAsset.trophy,\n"
    "                      label: context.tr('games'),\n"
    "                      value: '${challenge.challenger.gamesPlayed}',\n"
    "                      color: const Color(0xFFFFC94D),\n"
    "                    ),\n",
    path,
)
write(path, s)

# Platform/social page keeps existing friend and challenge plumbing, but its own
# competitive identity is now sourced from the visible RP profile.
path = 'lib/features/social/platform_social_screen.dart'
s = read(path)
s = replace_once(
    s,
    "import '../../localization/ux_copy.dart';\n",
    "import '../../localization/ux_copy.dart';\n"
    "import '../../models/rank_identity_models.dart';\n",
    path,
)
s = replace_once(
    s,
    "import '../../services/push_notification_service.dart';\n",
    "import '../../services/push_notification_service.dart';\n"
    "import '../../services/rank_identity_service.dart';\n",
    path,
)
s = replace_once(
    s,
    "import 'competitive_profile_card.dart';\n",
    "import 'profile_customization_screen.dart';\n"
    "import 'rank_identity_summary_card.dart';\n",
    path,
)
s = replace_once(
    s,
    '  CompetitiveProfile? _competitiveProfile;\n',
    '  RankIdentityProfile? _rankIdentityProfile;\n',
    path,
)
s = replace_once(
    s,
    "      final competitiveProfile = await _social.loadCompetitiveProfile();\n\n"
    "      if (!mounted) return;\n",
    "      RankIdentityProfile? rankIdentityProfile;\n"
    "      try {\n"
    "        rankIdentityProfile = await RankIdentityService.instance.refresh();\n"
    "      } catch (error) {\n"
    "        debugPrint('Visible RP profile unavailable in social screen: $error');\n"
    "      }\n\n"
    "      if (!mounted) return;\n",
    path,
)
s = replace_once(
    s,
    '        _competitiveProfile = competitiveProfile;\n',
    '        _rankIdentityProfile = rankIdentityProfile;\n',
    path,
)
pattern = re.compile(
    r"\s+CompetitiveProfileCard\(\n\s+profile:[\s\S]*?\n\s+\),\n\s+const SizedBox\(height: 12\),",
    re.MULTILINE,
)
replacement = """
                    if (_rankIdentityProfile != null)
                      RankIdentitySummaryCard(
                        profile: _rankIdentityProfile!,
                        onCustomize: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const ProfileCustomizationScreen(),
                          ),
                        ),
                      )
                    else
                      _MessageCard(
                        icon: Icons.workspace_premium_outlined,
                        title: context.tr('ranked'),
                        body: context.tr('try_again_when_connected'),
                      ),
                    const SizedBox(height: 12),"""
s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'{path}: could not replace legacy CompetitiveProfileCard block')
if '_competitiveProfile' in s or 'CompetitiveProfileCard' in s or 'currentElo' in s:
    raise SystemExit(f'{path}: hidden Elo presentation remains')
s = s.replace(
    "context.tr('player_rating_summary', <Object>[player.username, player.rating])",
    "'@${player.username} · ${context.tr('games_count', <Object>[player.gamesPlayed])}'",
)
write(path, s)

# Home compact identity uses the same selected avatar/frame/badges as profile.
path = 'lib/features/home/home_screen.dart'
s = read(path)
s = replace_once(
    s,
    "import '../../services/player_profile_service.dart';\n",
    "import '../../models/rank_identity_models.dart';\n"
    "import '../../services/player_profile_service.dart';\n"
    "import '../../services/rank_identity_service.dart';\n",
    path,
)
s = replace_once(
    s,
    '  PlayerProfilePreferences? _profile;\n',
    '  PlayerProfilePreferences? _profile;\n  RankIdentityProfile? _rankProfile;\n',
    path,
)
s = replace_once(
    s,
    '    unawaited(_loadProfile());\n',
    '    unawaited(_loadProfile());\n    unawaited(_loadRankProfile());\n',
    path,
)
marker = "  @override\n  Widget build(BuildContext context) {\n"
loader = (
    "  Future<void> _loadRankProfile() async {\n"
    "    try {\n"
    "      final profile = await RankIdentityService.instance.refresh();\n"
    "      if (mounted) setState(() => _rankProfile = profile);\n"
    "    } catch (_) {\n"
    "      // Home remains available offline and falls back to the local profile.\n"
    "    }\n"
    "  }\n\n"
)
if marker not in s:
    raise SystemExit(f'{path}: build marker missing')
s = s.replace(marker, loader + marker, 1)
s = replace_once(
    s,
    "                            _HomeTopBar(\n"
    "                              displayName:\n"
    "                                  _profile?.displayName ?? 'Sudoku Player',\n"
    "                              completedLevels: widget.store.completedLevelCount,\n",
    "                            _HomeTopBar(\n"
    "                              displayName: _rankProfile?.displayName ??\n"
    "                                  _profile?.displayName ??\n"
    "                                  'Sudoku Player',\n"
    "                              avatarKey: _rankProfile?.avatarKey ??\n"
    "                                  'home-profile-${_profile?.displayName ?? 'Sudoku Player'}',\n"
    "                              completedLevels: widget.store.completedLevelCount,\n",
    path,
)
s = replace_once(
    s,
    '    required this.displayName,\n    required this.completedLevels,\n',
    '    required this.displayName,\n    required this.avatarKey,\n    required this.completedLevels,\n',
    path,
)
s = replace_once(
    s,
    '  final String displayName;\n  final int completedLevels;\n',
    '  final String displayName;\n  final String avatarKey;\n  final int completedLevels;\n',
    path,
)
s = replace_once(
    s,
    "                            avatarKey: 'home-profile-$displayName',\n",
    '                            avatarKey: avatarKey,\n',
    path,
)
write(path, s)

# Owner-only native platform imagery remains visible to the owner after the
# PlayerAvatar remote-privacy hardening.
path = 'lib/features/social/rank_identity_summary_card.dart'
s = read(path)
s = replace_once(
    s,
    "import '../../models/rank_identity_models.dart';\n",
    "import '../../models/rank_identity_models.dart';\n"
    "import '../../services/platform_game_services.dart';\n",
    path,
)
s = replace_once(
    s,
    '    final stats = profile.stats;\n',
    "    final stats = profile.stats;\n"
    "    final platform = PlatformGameServices.instance.localPlayer.value;\n"
    "    final baseAvatarKey = RankIdentityKey.parse(profile.avatarKey).avatarKey;\n"
    "    final usePlatformAvatar = baseAvatarKey.startsWith('home-profile-');\n",
    path,
)
s = replace_once(
    s,
    "              final avatar = PlayerAvatar(\n"
    "                displayName: profile.displayName,\n"
    "                avatarKey: profile.avatarKey,\n"
    "                radius: compact ? 38 : 43,\n"
    "              );\n",
    "              final avatar = PlayerAvatar(\n"
    "                displayName: profile.displayName,\n"
    "                avatarKey: profile.avatarKey,\n"
    "                localAvatarBytes:\n"
    "                    usePlatformAvatar ? platform?.avatarBytes : null,\n"
    "                remoteApprovedImageUrl:\n"
    "                    usePlatformAvatar ? platform?.avatarUrl : null,\n"
    "                radius: compact ? 38 : 43,\n"
    "              );\n",
    path,
)
write(path, s)

path = 'lib/features/social/profile_customization_screen.dart'
s = read(path)
s = replace_once(
    s,
    '    final title = profile.unlockedTitles\n',
    "    final platform = PlatformGameServices.instance.localPlayer.value;\n"
    "    final previewBaseKey = RankIdentityKey.parse(identity).avatarKey;\n"
    "    final usePlatformAvatar = previewBaseKey.startsWith('home-profile-');\n"
    "    final title = profile.unlockedTitles\n",
    path,
)
s = replace_once(
    s,
    "          PlayerAvatar(\n"
    "            displayName: profile.displayName,\n"
    "            avatarKey: identity,\n"
    "            radius: 39,\n"
    "          ),\n",
    "          PlayerAvatar(\n"
    "            displayName: profile.displayName,\n"
    "            avatarKey: identity,\n"
    "            localAvatarBytes:\n"
    "                usePlatformAvatar ? platform?.avatarBytes : null,\n"
    "            remoteApprovedImageUrl:\n"
    "                usePlatformAvatar ? platform?.avatarUrl : null,\n"
    "            radius: 39,\n"
    "          ),\n",
    path,
)
write(path, s)

# Add source-level guardrails so hidden MMR cannot quietly reappear on public
# surfaces during later UI work.
Path('test/rank_identity_public_ui_contract_test.dart').write_text(
    r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player-facing competitive UI does not expose hidden MMR/Elo', () {
    final forbiddenByFile = <String, List<String>>{
      'lib/features/duel/matchmaking_stage.dart': <String>[
        "context.tr('rating')",
        'player.rating',
      ],
      'lib/features/social/platform_social_screen.dart': <String>[
        'currentElo',
        '_competitiveProfile',
        'CompetitiveProfileCard',
      ],
      'lib/features/social/social_hub_screen.dart': <String>[
        'challenge.challenger.rating',
        'player.rating,',
      ],
      'lib/features/social/friend_requests_screen.dart': <String>[
        'player.rating,',
      ],
      'lib/features/social/challenge_invitation_screen.dart': <String>[
        "value: '${challenge.challenger.rating}'",
      ],
    };

    for (final entry in forbiddenByFile.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final forbidden in entry.value) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: '${entry.key} must not expose hidden MMR via $forbidden',
        );
      }
    }
  });

  test('matchmaking presentation names visible RP explicitly', () {
    final source = File(
      'lib/features/duel/matchmaking_stage.dart',
    ).readAsStringSync();
    expect(source.contains('final int? rankPoints;'), isTrue);
    expect(source.contains("label: 'RP'"), isTrue);
  });
}
''',
    encoding='utf-8',
)

Path('backend/social_worker/test/rank_reward_migration.test.ts').write_text(
    r'''import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('rank reward migration contract', () => {
  const migration = readFileSync(
    new URL('../migrations/0024_rank_progression_identity.sql', import.meta.url),
    'utf8',
  );

  it('credits lifetime rank rewards exactly once through the primary-key boundary', () => {
    expect(migration).toContain('PRIMARY KEY(player_id, rank_key)');
    expect(migration).toContain('CREATE TRIGGER IF NOT EXISTS rank_reward_grant_apply');
    expect(migration).toContain('online_coins = online_coins + NEW.amount');
    expect(migration).toContain("'rank_reward:' || NEW.player_id || ':' || NEW.rank_key");
  });

  it('keeps rank rewards separate from match escrow and payout tables', () => {
    const trigger = migration.split('CREATE TRIGGER IF NOT EXISTS rank_reward_grant_apply')[1]
      ?.split('END;')[0] ?? '';
    expect(trigger).not.toContain('match_escrow');
    expect(trigger).not.toContain('match_settlements');
    expect(trigger).not.toContain('matches SET');
  });
});
''',
    encoding='utf-8',
)
