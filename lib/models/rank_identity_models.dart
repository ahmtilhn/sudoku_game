class RankTierInfo {
  const RankTierInfo({
    required this.key,
    required this.label,
    required this.league,
    required this.division,
    required this.minPoints,
  });

  final String key;
  final String label;
  final String league;
  final int division;
  final int minPoints;
}

const List<RankTierInfo> rankTierCatalog = <RankTierInfo>[
  RankTierInfo(
    key: 'bronze_3',
    label: 'Bronze III',
    league: 'bronze',
    division: 3,
    minPoints: 0,
  ),
  RankTierInfo(
    key: 'bronze_2',
    label: 'Bronze II',
    league: 'bronze',
    division: 2,
    minPoints: 300,
  ),
  RankTierInfo(
    key: 'bronze_1',
    label: 'Bronze I',
    league: 'bronze',
    division: 1,
    minPoints: 600,
  ),
  RankTierInfo(
    key: 'silver_3',
    label: 'Silver III',
    league: 'silver',
    division: 3,
    minPoints: 900,
  ),
  RankTierInfo(
    key: 'silver_2',
    label: 'Silver II',
    league: 'silver',
    division: 2,
    minPoints: 1200,
  ),
  RankTierInfo(
    key: 'silver_1',
    label: 'Silver I',
    league: 'silver',
    division: 1,
    minPoints: 1500,
  ),
  RankTierInfo(
    key: 'gold_3',
    label: 'Gold III',
    league: 'gold',
    division: 3,
    minPoints: 1800,
  ),
  RankTierInfo(
    key: 'gold_2',
    label: 'Gold II',
    league: 'gold',
    division: 2,
    minPoints: 2100,
  ),
  RankTierInfo(
    key: 'gold_1',
    label: 'Gold I',
    league: 'gold',
    division: 1,
    minPoints: 2400,
  ),
  RankTierInfo(
    key: 'platinum_3',
    label: 'Platinum III',
    league: 'platinum',
    division: 3,
    minPoints: 2700,
  ),
  RankTierInfo(
    key: 'platinum_2',
    label: 'Platinum II',
    league: 'platinum',
    division: 2,
    minPoints: 3000,
  ),
  RankTierInfo(
    key: 'platinum_1',
    label: 'Platinum I',
    league: 'platinum',
    division: 1,
    minPoints: 3300,
  ),
  RankTierInfo(
    key: 'master_3',
    label: 'Master III',
    league: 'master',
    division: 3,
    minPoints: 3600,
  ),
  RankTierInfo(
    key: 'master_2',
    label: 'Master II',
    league: 'master',
    division: 2,
    minPoints: 3900,
  ),
  RankTierInfo(
    key: 'master_1',
    label: 'Master I',
    league: 'master',
    division: 1,
    minPoints: 4200,
  ),
];

RankTierInfo rankTierForKey(String key) {
  return rankTierCatalog.firstWhere(
    (tier) => tier.key == key,
    orElse: () => rankTierCatalog.first,
  );
}

RankTierInfo rankTierForPoints(int points) {
  final safe = points < 0 ? 0 : points;
  for (var index = rankTierCatalog.length - 1; index >= 0; index--) {
    final tier = rankTierCatalog[index];
    if (safe >= tier.minPoints) return tier;
  }
  return rankTierCatalog.first;
}

class RankIdentityKey {
  const RankIdentityKey({
    required this.avatarKey,
    this.frameKey,
    this.decorationKeys = const <String>[],
  });

  final String avatarKey;
  final String? frameKey;
  final List<String> decorationKeys;

  bool get decorated => frameKey != null || decorationKeys.isNotEmpty;

  factory RankIdentityKey.parse(String raw) {
    final value = raw.trim();
    if (!value.startsWith('idv1|')) {
      return RankIdentityKey(avatarKey: value.isEmpty ? 'default' : value);
    }
    final parts = value.split('|');
    final avatar = parts.length > 1 && parts[1].trim().isNotEmpty
        ? parts[1].trim()
        : 'default';
    final frame = parts.length > 2 && parts[2].trim().isNotEmpty
        ? parts[2].trim()
        : null;
    final decorations = parts.length > 3
        ? parts[3]
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .take(3)
              .toList(growable: false)
        : const <String>[];
    return RankIdentityKey(
      avatarKey: avatar,
      frameKey: frame,
      decorationKeys: decorations,
    );
  }

  String encode() {
    final frame = frameKey ?? '';
    final decorations = decorationKeys.take(3).join(',');
    return 'idv1|$avatarKey|$frame|$decorations';
  }
}

class RankDecoration {
  const RankDecoration({
    required this.achievementId,
    required this.decorationKey,
    required this.rarity,
    required this.title,
    required this.description,
    required this.tier,
    required this.unlocked,
    required this.selected,
    this.slot,
  });

  final String achievementId;
  final String decorationKey;
  final String rarity;
  final String title;
  final String description;
  final String tier;
  final bool unlocked;
  final bool selected;
  final int? slot;

  factory RankDecoration.fromJson(Map<String, dynamic> json) {
    return RankDecoration(
      achievementId: json['achievementId']?.toString() ?? '',
      decorationKey: json['decorationKey']?.toString() ?? '',
      rarity: json['rarity']?.toString() ?? 'common',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      tier: json['tier']?.toString() ?? '',
      unlocked: json['unlocked'] == true,
      selected: json['selected'] == true,
      slot: (json['slot'] as num?)?.toInt(),
    );
  }
}

class RankRewardState {
  const RankRewardState({
    required this.rankKey,
    required this.rankName,
    required this.requiredPoints,
    required this.amount,
    required this.claimed,
  });

  final String rankKey;
  final String rankName;
  final int requiredPoints;
  final int amount;
  final bool claimed;

  factory RankRewardState.fromJson(Map<String, dynamic> json) {
    return RankRewardState(
      rankKey: json['rankKey']?.toString() ?? '',
      rankName: json['rankName']?.toString() ?? '',
      requiredPoints: (json['requiredPoints'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      claimed: json['claimed'] == true,
    );
  }
}

class RankProgressionStats {
  const RankProgressionStats({
    required this.rankedGames,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.winStreak,
    required this.bestWinStreak,
    required this.undefeatedStreak,
    required this.bestUndefeatedStreak,
    required this.perfectWins,
  });

  final int rankedGames;
  final int wins;
  final int losses;
  final int draws;
  final int winStreak;
  final int bestWinStreak;
  final int undefeatedStreak;
  final int bestUndefeatedStreak;
  final int perfectWins;

  factory RankProgressionStats.fromJson(Map<String, dynamic> json) {
    int value(String key) => (json[key] as num?)?.toInt() ?? 0;
    return RankProgressionStats(
      rankedGames: value('rankedGames'),
      wins: value('wins'),
      losses: value('losses'),
      draws: value('draws'),
      winStreak: value('winStreak'),
      bestWinStreak: value('bestWinStreak'),
      undefeatedStreak: value('undefeatedStreak'),
      bestUndefeatedStreak: value('bestUndefeatedStreak'),
      perfectWins: value('perfectWins'),
    );
  }
}

class RankTitleOption {
  const RankTitleOption({required this.key, required this.label});

  final String key;
  final String label;

  factory RankTitleOption.fromJson(Map<String, dynamic> json) {
    return RankTitleOption(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }
}

class RankIdentityProfile {
  const RankIdentityProfile({
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.selectedAvatarKey,
    required this.selectedFrameKey,
    required this.effectiveFrameKey,
    required this.selectedTitleKey,
    required this.unlockedTitles,
    required this.selectedDecorationAchievementIds,
    required this.selectedDecorationKeys,
    required this.rankPoints,
    required this.highestRankPoints,
    required this.rankKey,
    required this.rankName,
    required this.league,
    required this.division,
    required this.highestRankKey,
    required this.highestRankName,
    required this.pointsInDivision,
    required this.progress,
    required this.unlockedFrameKeys,
    required this.availableAvatarCount,
    required this.decorations,
    required this.rankRewards,
    required this.totalLifetimeRankReward,
    required this.stats,
    this.divisionSize,
    this.pointsToNext,
    this.nextRankKey,
    this.nextRankName,
  });

  final String publicId;
  final String username;
  final String displayName;
  final String avatarKey;
  final String selectedAvatarKey;
  final String selectedFrameKey;
  final String effectiveFrameKey;
  final String selectedTitleKey;
  final List<RankTitleOption> unlockedTitles;
  final List<String> selectedDecorationAchievementIds;
  final List<String> selectedDecorationKeys;
  final int rankPoints;
  final int highestRankPoints;
  final String rankKey;
  final String rankName;
  final String league;
  final int division;
  final String? nextRankKey;
  final String? nextRankName;
  final String highestRankKey;
  final String highestRankName;
  final int pointsInDivision;
  final int? divisionSize;
  final int? pointsToNext;
  final double progress;
  final List<String> unlockedFrameKeys;
  final int availableAvatarCount;
  final List<RankDecoration> decorations;
  final List<RankRewardState> rankRewards;
  final int totalLifetimeRankReward;
  final RankProgressionStats stats;

  factory RankIdentityProfile.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
    final decorationsJson = json['decorations'];
    final rewardsJson = json['rankRewards'];
    final titlesJson = json['unlockedTitles'];
    final statsJson = json['stats'];
    return RankIdentityProfile(
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Sudoku Player',
      avatarKey: json['avatarKey']?.toString() ?? 'default',
      selectedAvatarKey: json['selectedAvatarKey']?.toString() ?? 'default',
      selectedFrameKey: json['selectedFrameKey']?.toString() ?? 'auto',
      effectiveFrameKey: json['effectiveFrameKey']?.toString() ?? 'bronze_3',
      selectedTitleKey: json['selectedTitleKey']?.toString() ?? '',
      unlockedTitles: titlesJson is List
          ? titlesJson
                .whereType<Map>()
                .map(
                  (item) =>
                      RankTitleOption.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <RankTitleOption>[],
      selectedDecorationAchievementIds: strings(
        json['selectedDecorationAchievementIds'],
      ),
      selectedDecorationKeys: strings(json['selectedDecorationKeys']),
      rankPoints: (json['rankPoints'] as num?)?.toInt() ?? 0,
      highestRankPoints: (json['highestRankPoints'] as num?)?.toInt() ?? 0,
      rankKey: json['rankKey']?.toString() ?? 'bronze_3',
      rankName: json['rankName']?.toString() ?? 'Bronze III',
      league: json['league']?.toString() ?? 'bronze',
      division: (json['division'] as num?)?.toInt() ?? 3,
      nextRankKey: json['nextRankKey']?.toString(),
      nextRankName: json['nextRankName']?.toString(),
      highestRankKey: json['highestRankKey']?.toString() ?? 'bronze_3',
      highestRankName: json['highestRankName']?.toString() ?? 'Bronze III',
      pointsInDivision: (json['pointsInDivision'] as num?)?.toInt() ?? 0,
      divisionSize: (json['divisionSize'] as num?)?.toInt(),
      pointsToNext: (json['pointsToNext'] as num?)?.toInt(),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      unlockedFrameKeys: strings(json['unlockedFrameKeys']),
      availableAvatarCount:
          (json['availableAvatarCount'] as num?)?.toInt() ?? 96,
      decorations: decorationsJson is List
          ? decorationsJson
                .whereType<Map>()
                .map(
                  (item) =>
                      RankDecoration.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <RankDecoration>[],
      rankRewards: rewardsJson is List
          ? rewardsJson
                .whereType<Map>()
                .map(
                  (item) =>
                      RankRewardState.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <RankRewardState>[],
      totalLifetimeRankReward:
          (json['totalLifetimeRankReward'] as num?)?.toInt() ?? 12000,
      stats: RankProgressionStats.fromJson(
        statsJson is Map
            ? statsJson.cast<String, dynamic>()
            : const <String, dynamic>{},
      ),
    );
  }
}

class RankLeaderboardEntry {
  const RankLeaderboardEntry({
    required this.rank,
    required this.publicId,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.rankPoints,
    required this.rankKey,
    required this.rankName,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.winRate,
  });

  final int rank;
  final String publicId;
  final String username;
  final String displayName;
  final String avatarKey;
  final int rankPoints;
  final String rankKey;
  final String rankName;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final double winRate;

  factory RankLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return RankLeaderboardEntry(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      publicId: json['publicId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      avatarKey: json['avatarKey']?.toString() ?? 'default',
      rankPoints: (json['rankPoints'] as num?)?.toInt() ?? 0,
      rankKey: json['rankKey']?.toString() ?? 'bronze_3',
      rankName: json['rankName']?.toString() ?? 'Bronze III',
      gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble() ?? 0,
    );
  }
}
