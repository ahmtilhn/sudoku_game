import 'package:flutter/material.dart';

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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF3AA9FF).withValues(alpha: .32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PlayerAvatar(
                  displayName: displayName,
                  avatarKey: profile.avatarKey,
                  remoteApprovedImageUrl: platformPlayer?.avatarUrl,
                  radius: 28,
                  semanticLabel: context.tr('player_avatar_semantics', <Object>[
                    displayName,
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (profile.privateProfile) ...[
                            const SizedBox(width: 6),
                            DuelAssetIcon(
                              DuelAsset.lock,
                              size: 16,
                              color: Colors.white.withValues(alpha: .62),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '@${profile.username} · ${profile.publicId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .56),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _RankBadge(label: profile.rankName),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ProfileStat(
                  label: context.tr('current_elo'),
                  value: '${profile.currentElo}',
                ),
                _ProfileStat(
                  label: context.tr('rank'),
                  value: profile.rank == null ? '-' : '#${profile.rank}',
                ),
                _ProfileStat(
                  label: context.tr('wins_losses_draws'),
                  value: '${profile.wins}/${profile.losses}/${profile.draws}',
                ),
                _ProfileStat(
                  label: context.tr('win_rate'),
                  value: '${(profile.winRate * 100).round()}%',
                ),
                _ProfileStat(
                  label: context.tr('win_streak'),
                  value: '${profile.winStreak}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('achievement_showcase'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            if (profile.achievementShowcase.isEmpty)
              Text(
                context.tr('achievement_showcase_empty'),
                style: TextStyle(color: Colors.white.withValues(alpha: .62)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final achievement in profile.achievementShowcase.take(3))
                    _ProfileChip(
                      asset: DuelAsset.trophy,
                      label: achievement.title,
                      color: const Color(0xFFFFC94D),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF3AA9FF).withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF3AA9FF).withValues(alpha: .36),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9FD4FF),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _ProfileChip(
      asset: DuelAsset.trophy,
      label: '$label: $value',
      color: const Color(0xFF29D398),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.asset,
    required this.label,
    required this.color,
  });

  final String asset;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuelAssetIcon(asset, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
