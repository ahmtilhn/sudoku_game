import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../localization/app_strings.dart';
import '../../services/platform_game_services.dart';
import '../../services/social_api_client.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';

class CompetitiveProfileCard extends StatelessWidget {
  const CompetitiveProfileCard({super.key, required this.profile});

  final CompetitiveProfile profile;

  @override
  Widget build(BuildContext context) {
    final platformPlayer = PlatformGameServices.instance.localPlayer.value;
    final platformDisplayName = platformPlayer?.effectiveDisplayName.trim();
    final displayName =
        platformDisplayName != null && platformDisplayName.isNotEmpty
        ? platformDisplayName
        : profile.displayName;
    final gamesPlayed = profile.wins + profile.losses + profile.draws;
    final winRate = '${(profile.winRate * 100).round()}%';
    final hasAchievements =
        profile.achievementCount > 0 || profile.achievementShowcase.isNotEmpty;

    return _ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileHeader(
            profile: profile,
            displayName: displayName,
            username: profile.username,
            publicId: profile.publicId,
            avatarKey: profile.avatarKey,
            privateProfile: profile.privateProfile,
            platformName: _platformLabel(platformPlayer),
            platformConnected: platformPlayer != null,
            platformPlayer: platformPlayer,
            gamesPlayed: gamesPlayed,
            winRate: winRate,
          ),
          const SizedBox(height: 12),
          _ProfilePerformanceStrip(
            profile: profile,
            gamesPlayed: gamesPlayed,
            winRate: winRate,
          ),
          if (hasAchievements) ...[
            const SizedBox(height: 12),
            _AchievementSummary(profile: profile),
          ],
        ],
      ),
    );
  }

  String _platformLabel(PlatformPlayer? player) {
    if (player == null) return 'Account';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return 'Game Center';
    }
    if (player.platform.toLowerCase().contains('ios')) return 'Game Center';
    if (player.platform.toLowerCase().contains('gamecenter')) {
      return 'Game Center';
    }
    return 'Google Play Games';
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: child,
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.displayName,
    required this.username,
    required this.publicId,
    required this.avatarKey,
    required this.privateProfile,
    required this.platformName,
    required this.platformConnected,
    required this.platformPlayer,
    required this.gamesPlayed,
    required this.winRate,
  });

  final CompetitiveProfile profile;
  final String displayName;
  final String username;
  final String publicId;
  final String avatarKey;
  final bool privateProfile;
  final String platformName;
  final bool platformConnected;
  final PlatformPlayer? platformPlayer;
  final int gamesPlayed;
  final String winRate;

  @override
  Widget build(BuildContext context) {
    final nextMilestone = ((profile.currentElo ~/ 100) + 1) * 100;
    final floor = nextMilestone - 100;
    final progress = ((profile.currentElo - floor) / 100).clamp(0.0, 1.0);
    final remaining = (nextMilestone - profile.currentElo).clamp(0, 9999);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 430 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25;
        final avatar = DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF3AA9FF).withValues(alpha: .32),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: PlayerAvatar(
              displayName: displayName,
              avatarKey: avatarKey,
              localAvatarBytes: platformPlayer?.avatarBytes,
              remoteApprovedImageUrl: platformPlayer?.avatarUrl,
              radius: compact ? 34 : 38,
              semanticLabel: context.tr('player_avatar_semantics', <Object>[
                displayName,
              ]),
            ),
          ),
        );
        final identity = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 22 : 24,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              _IdentityLine(username: username, publicId: publicId),
            ],
          ),
        );

        final status = Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _RankBadge(label: profile.rankName),
            _SoftBadge(
              label: platformConnected ? platformName : context.tr('account'),
              color: platformConnected
                  ? const Color(0xFF29D398)
                  : const Color(0xFF8EA2AD),
              asset: DuelAsset.profile,
            ),
            if (privateProfile)
              _SoftBadge(
                label: context.tr('private'),
                color: const Color(0xFFB7A9FF),
                asset: DuelAsset.lock,
              ),
          ],
        );

        final rating = Container(
          width: compact ? double.infinity : 168,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF66C7FF).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF66C7FF).withValues(alpha: .18),
            ),
          ),
          child: Column(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(
                '${profile.currentElo}',
                style: const TextStyle(
                  color: Color(0xFF66C7FF),
                  fontSize: 42,
                  height: .92,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                context.tr('home_rating_label'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .52),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: Colors.white.withValues(alpha: .08),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF66C7FF),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                remaining == 0 ? '$floor-$nextMilestone' : '$remaining to next',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .56),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );

        final detailRail = privateProfile
            ? const SizedBox.shrink()
            : Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _EloMicroMetric(
                    label: context.tr('season_peak'),
                    value: '${profile.seasonPeak}',
                    color: const Color(0xFFB7A9FF),
                  ),
                  _EloMicroMetric(
                    label: context.tr('win_rate'),
                    value: winRate,
                    color: const Color(0xFF29D398),
                  ),
                  _EloMicroMetric(
                    label: context.tr('record'),
                    value: context.tr('games_count', <Object>[gamesPlayed]),
                    color: const Color(0xFF3AA9FF),
                  ),
                ],
              );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 14 : 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .24),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF66C7FF).withValues(alpha: .16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [avatar, const SizedBox(width: 14), identity],
                    ),
                    const SizedBox(height: 13),
                    status,
                    const SizedBox(height: 12),
                    rating,
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: 15),
                    identity,
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 250),
                          child: status,
                        ),
                        const SizedBox(height: 12),
                        rating,
                      ],
                    ),
                  ],
                ),
              if (!privateProfile) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: Colors.white.withValues(alpha: .07)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const DuelAssetIcon(
                      DuelAsset.leaderboardCrownPro,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: detailRail),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _SoftBadge(
      label: label,
      color: const Color(0xFF66C7FF),
      asset: DuelAsset.trophy,
    );
  }
}

class _IdentityLine extends StatelessWidget {
  const _IdentityLine({required this.username, required this.publicId});

  final String username;
  final String publicId;

  @override
  Widget build(BuildContext context) {
    final label = publicId.isEmpty ? '@$username' : '@$username · $publicId';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: publicId.isEmpty
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: publicId));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('copy_friend_id'))),
                );
              },
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 130,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .68),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (publicId.isNotEmpty) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: .64),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePerformanceStrip extends StatelessWidget {
  const _ProfilePerformanceStrip({
    required this.profile,
    required this.gamesPlayed,
    required this.winRate,
  });

  final CompetitiveProfile profile;
  final int gamesPlayed;
  final String winRate;

  @override
  Widget build(BuildContext context) {
    final cells = [
      _PerformanceCellData(
        label: context.tr('wins'),
        value: '${profile.wins}',
        asset: DuelAsset.trophy,
        accent: const Color(0xFF66C7FF),
      ),
      _PerformanceCellData(
        label: context.tr('losses'),
        value: '${profile.losses}',
        asset: DuelAsset.grid,
        accent: const Color(0xFFB7A9FF),
      ),
      _PerformanceCellData(
        label: context.tr('games'),
        value: '$gamesPlayed',
        asset: DuelAsset.grid,
        accent: const Color(0xFF3AA9FF),
      ),
      _PerformanceCellData(
        label: context.tr('win_rate'),
        value: winRate,
        asset: DuelAsset.people,
        accent: const Color(0xFF29D398),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 2;
        final width = (constraints.maxWidth - ((columns - 1) * 7)) / columns;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final cell in cells)
                  SizedBox(
                    width: width,
                    child: _PerformanceCell(data: cell),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PerformanceCellData {
  const _PerformanceCellData({
    required this.asset,
    required this.value,
    required this.label,
    required this.accent,
  });

  final String asset;
  final String value;
  final String label;
  final Color accent;
}

class _PerformanceCell extends StatelessWidget {
  const _PerformanceCell({required this.data});

  final _PerformanceCellData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: data.accent.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: data.accent.withValues(alpha: .16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            DuelAssetIcon(data.asset, size: 18, color: data.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .58),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EloMicroMetric extends StatelessWidget {
  const _EloMicroMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .55),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementSummary extends StatelessWidget {
  const _AchievementSummary({required this.profile});

  final CompetitiveProfile profile;

  @override
  Widget build(BuildContext context) {
    final showcase = profile.achievementShowcase.take(4).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DuelAssetIcon(
                  DuelAsset.trophy,
                  size: 20,
                  color: Color(0xFFB7A9FF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('achievement_showcase'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${profile.achievementCount}',
                  style: const TextStyle(
                    color: Color(0xFFB7A9FF),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (showcase.isEmpty)
              Text(
                context.tr('achievement_showcase_empty'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .62),
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final achievement in showcase)
                    _SoftBadge(
                      label: achievement.title,
                      color: const Color(0xFFB7A9FF),
                      asset: DuelAsset.trophy,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SoftBadge extends StatelessWidget {
  const _SoftBadge({
    required this.label,
    required this.color,
    required this.asset,
  });

  final String label;
  final Color color;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuelAssetIcon(asset, size: 14, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 120,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
