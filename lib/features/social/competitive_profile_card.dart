import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/social_api_client.dart';
import '../../widgets/player_avatar.dart';

class CompetitiveProfileCard extends StatelessWidget {
  const CompetitiveProfileCard({super.key, required this.profile});

  final CompetitiveProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final country = profile.country == null || profile.country!.isEmpty
        ? context.tr('country_not_set')
        : profile.country!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PlayerAvatar(
                  displayName: profile.displayName,
                  avatarKey: profile.avatarKey,
                  radius: 28,
                  semanticLabel: context.tr('player_avatar_semantics', <Object>[
                    profile.displayName,
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
                              profile.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (profile.privateProfile) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '@${profile.username} · ${profile.publicId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
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
                  label: context.tr('season_peak'),
                  value: '${profile.seasonPeak}',
                ),
                _ProfileStat(label: context.tr('country'), value: country),
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
                _ProfileStat(
                  label: context.tr('tournament_entries'),
                  value: '${profile.tournamentEntries}',
                ),
                _ProfileStat(
                  label: context.tr('tournament_podiums'),
                  value: '${profile.tournamentPodiums}',
                ),
                _ProfileStat(
                  label: context.tr('country_contributions'),
                  value: '${profile.countryContributions}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('achievement_showcase'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (profile.achievementShowcase.isEmpty)
              Text(
                context.tr('achievement_showcase_empty'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final achievement in profile.achievementShowcase.take(3))
                    Chip(
                      avatar: const Icon(Icons.emoji_events_outlined, size: 18),
                      label: Text(achievement.title),
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
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
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
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value'),
    );
  }
}
