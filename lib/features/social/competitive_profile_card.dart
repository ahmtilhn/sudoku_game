import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/app_strings.dart';
import '../../services/social_api_client.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';

/// Compatibility card for the legacy friends/social surface.
///
/// Hidden Elo/MMR deliberately is not rendered here. The player-facing rank,
/// RP progress, earned frame, badges and title live in [ProfileHubScreen] and
/// the additive rank identity APIs. Keeping this widget free of Elo prevents
/// the old social page from exposing the matchmaking skill signal while
/// preserving the existing social/friend data contract.
class CompetitiveProfileCard extends StatelessWidget {
  const CompetitiveProfileCard({super.key, required this.profile});

  final CompetitiveProfile profile;

  @override
  Widget build(BuildContext context) {
    final gamesPlayed = profile.wins + profile.losses + profile.draws;
    final winRate = '${(profile.winRate.clamp(0, 1) * 100).round()}%';
    final hasAchievements =
        profile.achievementCount > 0 || profile.achievementShowcase.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF3AA9FF).withValues(alpha: .34),
                    width: 2,
                  ),
                ),
                child: PlayerAvatar(
                  displayName: profile.displayName,
                  avatarKey: profile.avatarKey,
                  radius: 34,
                  semanticLabel: context.tr(
                    'player_avatar_semantics',
                    <Object>[profile.displayName],
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _IdentityLine(
                      username: profile.username,
                      publicId: profile.publicId,
                    ),
                  ],
                ),
              ),
              if (profile.privateProfile)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: DuelAssetIcon(DuelAsset.lock, size: 26),
                ),
            ],
          ),
          if (!profile.privateProfile) ...[
            const SizedBox(height: 13),
            Divider(height: 1, color: Colors.white.withValues(alpha: .07)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: context.tr('record'),
                    value: '$gamesPlayed',
                    color: const Color(0xFF66C7FF),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Metric(
                    label: context.tr('win_rate'),
                    value: winRate,
                    color: const Color(0xFF29D398),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Metric(
                    label: context.tr('wins'),
                    value: '${profile.wins}',
                    color: const Color(0xFFFFC94D),
                  ),
                ),
              ],
            ),
          ],
          if (hasAchievements) ...[
            const SizedBox(height: 13),
            _AchievementSummary(profile: profile),
          ],
        ],
      ),
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
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .64),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .48),
              fontSize: 9,
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
    final showcase = profile.achievementShowcase;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFB7A9FF).withValues(alpha: .07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFFB7A9FF).withValues(alpha: .14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('achievements'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          if (showcase.isEmpty)
            Text(
              '${profile.achievementCount}',
              style: const TextStyle(
                color: Color(0xFFB7A9FF),
                fontWeight: FontWeight.w900,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final achievement in showcase.take(3))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    child: Text(
                      achievement.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
