import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final platformDisplayName = platformPlayer?.displayName.trim();
    final displayName =
        platformDisplayName != null && platformDisplayName.isNotEmpty
        ? platformDisplayName
        : profile.displayName;
    final gamesPlayed = profile.wins + profile.losses + profile.draws;
    final winRate = '${(profile.winRate * 100).round()}%';

    return _ProfileSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileHeader(
            displayName: displayName,
            username: profile.username,
            publicId: profile.publicId,
            avatarKey: profile.avatarKey,
            privateProfile: profile.privateProfile,
            platformName: _platformLabel(platformPlayer),
            platformConnected: platformPlayer != null,
            platformPlayer: platformPlayer,
            rankName: profile.rankName,
            currentElo: profile.currentElo,
          ),
          const SizedBox(height: 16),
          _ProfileStatGrid(
            stats: [
              _ProfileStatData(
                asset: DuelAsset.trophy,
                value: '${profile.wins}',
                label: 'Wins',
                accent: const Color(0xFFFFC94D),
              ),
              _ProfileStatData(
                asset: DuelAsset.grid,
                value: '${profile.losses}',
                label: 'Losses',
                accent: const Color(0xFFFF8A3D),
              ),
              _ProfileStatData(
                asset: DuelAsset.grid,
                value: '$gamesPlayed',
                label: 'Games',
                accent: const Color(0xFF3AA9FF),
              ),
              _ProfileStatData(
                asset: DuelAsset.people,
                value: winRate,
                label: context.tr('win_rate'),
                accent: const Color(0xFF29D398),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RatingPanel(profile: profile),
          const SizedBox(height: 12),
          _AchievementSummary(profile: profile),
        ],
      ),
    );
  }

  String _platformLabel(PlatformPlayer? player) {
    if (player == null) return 'Account';
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF162833).withValues(alpha: .96),
            const Color(0xFF0E181D).withValues(alpha: .96),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.username,
    required this.publicId,
    required this.avatarKey,
    required this.privateProfile,
    required this.platformName,
    required this.platformConnected,
    required this.platformPlayer,
    required this.rankName,
    required this.currentElo,
  });

  final String displayName;
  final String username;
  final String publicId;
  final String avatarKey;
  final bool privateProfile;
  final String platformName;
  final bool platformConnected;
  final PlatformPlayer? platformPlayer;
  final String rankName;
  final int currentElo;

  @override
  Widget build(BuildContext context) {
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
        final identity = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 20 : 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (privateProfile) ...[
                  const SizedBox(width: 6),
                  DuelAssetIcon(
                    DuelAsset.lock,
                    size: 16,
                    color: Colors.white.withValues(alpha: .62),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '@$username · $publicId',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .62),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            _FriendIdPill(publicId: publicId),
          ],
        );

        final status = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RankBadge(label: rankName),
            _SoftBadge(
              label: '$currentElo ELO',
              color: const Color(0xFFFFC94D),
              asset: DuelAsset.leaderboardCrownPro,
            ),
            _SoftBadge(
              label: platformConnected ? '$platformName Connected' : 'Account',
              color: platformConnected
                  ? const Color(0xFF29D398)
                  : const Color(0xFF8EA2AD),
              asset: DuelAsset.profile,
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 14),
                  Expanded(child: identity),
                ],
              ),
              const SizedBox(height: 12),
              status,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(child: identity),
            const SizedBox(width: 12),
            Flexible(child: status),
          ],
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
      color: const Color(0xFF3AA9FF),
      asset: DuelAsset.trophy,
    );
  }
}

class _FriendIdPill extends StatelessWidget {
  const _FriendIdPill({required this.publicId});

  final String publicId;

  @override
  Widget build(BuildContext context) {
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
                  maxWidth: MediaQuery.sizeOf(context).width - 126,
                ),
                child: Text(
                  publicId.isEmpty ? 'Friend ID' : publicId,
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

class _ProfileStatGrid extends StatelessWidget {
  const _ProfileStatGrid({required this.stats});

  final List<_ProfileStatData> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 460 ? 2 : 4;
        final width = (constraints.maxWidth - ((columns - 1) * 8)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final stat in stats) SizedBox(width: width, child: stat),
          ],
        );
      },
    );
  }
}

class _ProfileStatData extends StatelessWidget {
  const _ProfileStatData({
    required this.asset,
    required this.value,
    required this.label,
    required this.accent,
  });

  final String asset;
  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DuelAssetIcon(asset, size: 20, color: accent),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .58),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingPanel extends StatelessWidget {
  const _RatingPanel({required this.profile});

  final CompetitiveProfile profile;

  @override
  Widget build(BuildContext context) {
    final nextMilestone = ((profile.currentElo ~/ 100) + 1) * 100;
    final floor = nextMilestone - 100;
    final progress = ((profile.currentElo - floor) / 100).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0A151A).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF3AA9FF).withValues(alpha: .18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.rankName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${profile.currentElo} ELO',
                  style: const TextStyle(
                    color: Color(0xFFFFC94D),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF3AA9FF),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Peak ${profile.seasonPeak}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'Next $nextMilestone',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .62),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
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
        color: Colors.black.withValues(alpha: .13),
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
                  color: Color(0xFFFFC94D),
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
                    color: Color(0xFFFFC94D),
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
                      color: const Color(0xFFFFC94D),
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
