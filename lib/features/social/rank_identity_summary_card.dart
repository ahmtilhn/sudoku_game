import 'package:flutter/material.dart';

import '../../models/rank_identity_models.dart';
import '../../widgets/player_avatar.dart';

class RankIdentitySummaryCard extends StatelessWidget {
  const RankIdentitySummaryCard({
    super.key,
    required this.profile,
    required this.onCustomize,
  });

  final RankIdentityProfile profile;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;
    final winRate = stats.rankedGames == 0
        ? 0
        : ((stats.wins / stats.rankedGames) * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 470;
              final avatar = PlayerAvatar(
                displayName: profile.displayName,
                avatarKey: profile.avatarKey,
                radius: compact ? 38 : 43,
              );
              final identity = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '@${profile.username}${profile.publicId.isEmpty ? '' : ' · ${profile.publicId}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .56),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (profile.selectedTitleKey.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _TitlePill(label: _selectedTitleLabel(profile)),
                  ],
                ],
              );
              final rank = _RankBlock(profile: profile);
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        avatar,
                        const SizedBox(width: 14),
                        Expanded(child: identity),
                      ],
                    ),
                    const SizedBox(height: 14),
                    rank,
                  ],
                );
              }
              return Row(
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  Expanded(child: identity),
                  const SizedBox(width: 12),
                  SizedBox(width: 220, child: rank),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _ProgressStrip(profile: profile),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Metric(label: 'Ranked', value: '${stats.rankedGames}'),
              _Metric(label: 'Wins', value: '${stats.wins}'),
              _Metric(label: 'Win rate', value: '$winRate%'),
              _Metric(label: 'Best streak', value: '${stats.bestWinStreak}'),
              _Metric(
                label: 'Best unbeaten',
                value: '${stats.bestUndefeatedStreak}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Peak: ${profile.highestRankName} · ${profile.highestRankPoints} RP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .60),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: onCustomize,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Customize'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _selectedTitleLabel(RankIdentityProfile profile) {
    for (final title in profile.unlockedTitles) {
      if (title.key == profile.selectedTitleKey) return title.label;
    }
    return profile.selectedTitleKey;
  }
}

class _RankBlock extends StatelessWidget {
  const _RankBlock({required this.profile});

  final RankIdentityProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.rankName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${profile.rankPoints} RP',
            style: const TextStyle(
              color: Color(0xFF66C7FF),
              fontSize: 25,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.profile});

  final RankIdentityProfile profile;

  @override
  Widget build(BuildContext context) {
    final next = profile.nextRankName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: profile.progress.clamp(0, 1),
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: .08),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF66C7FF)),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Text(
              profile.divisionSize == null
                  ? '${profile.pointsInDivision} RP above Master I'
                  : '${profile.pointsInDivision}/${profile.divisionSize} RP',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .58),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              next == null
                  ? 'Top rank'
                  : '${profile.pointsToNext ?? 0} RP to $next',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .58),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .52),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitlePill extends StatelessWidget {
  const _TitlePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD9A5FF).withValues(alpha: .11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFD9A5FF).withValues(alpha: .25),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFE8C8FF),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
