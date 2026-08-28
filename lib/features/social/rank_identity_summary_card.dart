import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../localization/app_strings.dart';

import '../../models/rank_identity_models.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/rank_emblem.dart';

class RankIdentitySummaryCard extends StatelessWidget {
  const RankIdentitySummaryCard({
    super.key,
    required this.profile,
    required VoidCallback onCustomize,
  });

  final RankIdentityProfile profile;

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;
    final winRate = stats.rankedGames == 0
        ? 0
        : ((stats.wins / stats.rankedGames) * 100).round();
    final accent = _rankAccent(profile.rankKey);

    return _PremiumIdentityPanel(
      profile: profile,
      accent: accent,
      winRate: winRate,
    );
  }
}

class _PremiumIdentityPanel extends StatelessWidget {
  const _PremiumIdentityPanel({
    required this.profile,
    required this.accent,
    required this.winRate,
  });

  final RankIdentityProfile profile;
  final Color accent;
  final int winRate;

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF10212C).withValues(alpha: .96),
            const Color(0xFF09151D).withValues(alpha: .96),
            const Color(0xFF071118).withValues(alpha: .98),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: .48), width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .32),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: accent.withValues(alpha: .08),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          children: [
            Positioned(
              left: -66,
              top: -72,
              child: _GlowOrb(color: accent, size: 190, opacity: .17),
            ),
            const Positioned(
              right: -70,
              bottom: -90,
              child: _GlowOrb(
                color: Color(0xFF2F9BFF),
                size: 210,
                opacity: .10,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _SubtleGridPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _IdentityHeroRow(profile: profile, accent: accent),
                  const SizedBox(height: 10),
                  _ProgressStrip(profile: profile, accent: accent),
                  const SizedBox(height: 10),
                  _CompactMetricGrid(
                    ranked: stats.rankedGames,
                    wins: stats.wins,
                    winRate: winRate,
                    bestStreak: stats.bestWinStreak,
                    bestUnbeaten: stats.bestUndefeatedStreak,
                    accent: accent,
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

class _IdentityHeroRow extends StatelessWidget {
  const _IdentityHeroRow({required this.profile, required this.accent});

  final RankIdentityProfile profile;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final avatarRadius = compact ? 43.0 : 49.0;
        final rankWidth = compact ? 72.0 : 82.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _AvatarShowcase(
              profile: profile,
              accent: accent,
              radius: avatarRadius,
            ),
            SizedBox(width: compact ? 9 : 12),
            Expanded(
              child: _IdentityDetails(
                profile: profile,
                accent: accent,
                compact: compact,
              ),
            ),
            SizedBox(width: compact ? 6 : 9),
            SizedBox(
              width: rankWidth,
              child: _RankShowcase(profile: profile, accent: accent),
            ),
          ],
        );
      },
    );
  }
}

class _AvatarShowcase extends StatelessWidget {
  const _AvatarShowcase({
    required this.profile,
    required this.accent,
    required this.radius,
  });

  final RankIdentityProfile profile;
  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return SizedBox.square(
      dimension: size + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size + 5,
            height: size + 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .26),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          PlayerAvatar(
            displayName: profile.displayName,
            avatarKey: profile.avatarKey,
            radius: radius,
          ),
        ],
      ),
    );
  }
}

class _IdentityDetails extends StatelessWidget {
  const _IdentityDetails({
    required this.profile,
    required this.accent,
    required this.compact,
  });

  final RankIdentityProfile profile;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              color: accent,
              size: compact ? 16 : 18,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                profile.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 20 : 23,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '@${profile.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .58),
            fontSize: compact ? 10.5 : 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (profile.publicId.isNotEmpty) ...[
          const SizedBox(height: 5),
          _PublicIdPill(publicId: profile.publicId, accent: accent),
        ],
        if (profile.selectedTitleKey.isNotEmpty) ...[
          const SizedBox(height: 5),
          _TitlePill(label: _selectedTitleLabel(profile), accent: accent),
        ],
        const SizedBox(height: 7),
        _RpHighlight(profile: profile, accent: accent, compact: compact),
      ],
    );
  }

  String _selectedTitleLabel(RankIdentityProfile profile) {
    for (final title in profile.unlockedTitles) {
      if (title.key == profile.selectedTitleKey) return title.label;
    }
    return profile.selectedTitleKey;
  }
}

class _PublicIdPill extends StatelessWidget {
  const _PublicIdPill({required this.publicId, required this.accent});

  final String publicId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 165),
      padding: const EdgeInsets.fromLTRB(7, 3, 4, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              publicId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .70),
                fontSize: 9.5,
                letterSpacing: .25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 3),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: publicId));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(context.tr('player_id_copied')),
                    duration: Duration(milliseconds: 900),
                  ),
                );
            },
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.copy_rounded,
                size: 11,
                color: accent.withValues(alpha: .86),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RpHighlight extends StatelessWidget {
  const _RpHighlight({
    required this.profile,
    required this.accent,
    required this.compact,
  });

  final RankIdentityProfile profile;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF10263A).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: accent.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .06), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 22 : 25,
            height: compact ? 22 : 25,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .14),
              border: Border.all(color: accent.withValues(alpha: .45)),
            ),
            child: Icon(
              Icons.hexagon_rounded,
              color: accent,
              size: compact ? 14 : 16,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              context.tr('rp_value', <Object>[profile.rankPoints]),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                color: const Color(0xFF67C8FF),
                fontSize: compact ? 21 : 25,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: .2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankShowcase extends StatelessWidget {
  const _RankShowcase({required this.profile, required this.accent});

  final RankIdentityProfile profile;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 7, 5, 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .20),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: .25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RankEmblem(
            rankKey: profile.rankKey,
            size: 49,
            semanticLabel: context.tr('rank_name_label', <Object>[
              profile.rankName,
            ]),
          ),
          const SizedBox(height: 4),
          Text(
            profile.rankName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 10.5,
              height: 1.0,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.profile, required this.accent});

  final RankIdentityProfile profile;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final next = profile.nextRankName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: profile.progress.clamp(0.0, 1.0).toDouble(),
            minHeight: 7,
            backgroundColor: Colors.white.withValues(alpha: .075),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                profile.divisionSize == null
                    ? context.tr('rp_above_master_i', <Object>[
                        profile.pointsInDivision,
                      ])
                    : context.tr('rp_progress_fraction', <Object>[
                        profile.pointsInDivision,
                        profile.divisionSize ?? 0,
                      ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .58),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                next == null
                    ? context.tr('top_rank')
                    : context.tr('rp_to_rank', <Object>[
                        profile.pointsToNext ?? 0,
                        next,
                      ]),
                maxLines: 1,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .58),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactMetricGrid extends StatelessWidget {
  const _CompactMetricGrid({
    required this.ranked,
    required this.wins,
    required this.winRate,
    required this.bestStreak,
    required this.bestUnbeaten,
    required this.accent,
  });

  final int ranked;
  final int wins;
  final int winRate;
  final int bestStreak;
  final int bestUnbeaten;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricChip(
                asset: 'assets/profile/ranked.png',
                value: '$ranked',
                label: context.tr('ranked_label'),
                accent: accent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _MetricChip(
                asset: 'assets/profile/wins.png',
                value: '$wins',
                label: context.tr('wins_label'),
                accent: accent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _MetricChip(
                asset: 'assets/profile/winrate.png',
                value: '$winRate%',
                label: context.tr('win_rate'),
                accent: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _MetricChip(
                asset: 'assets/profile/beststreake.png',
                value: '$bestStreak',
                label: context.tr('best_streak'),
                accent: accent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _MetricChip(
                asset: 'assets/profile/bestunbeaten.png',
                value: '$bestUnbeaten',
                label: context.tr('best_unbeaten'),
                accent: accent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
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
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .075)),
      ),
      child: Row(
        children: [
          Image.asset(
            asset,
            width: 23,
            height: 23,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) =>
                Icon(Icons.auto_awesome_rounded, size: 19, color: accent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: .95,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .54),
                    fontSize: 9.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitlePill extends StatelessWidget {
  const _TitlePill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 155),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accent.withValues(alpha: .96),
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _SubtleGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .018)
      ..strokeWidth = .7;
    const step = 42.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SubtleGridPainter oldDelegate) => false;
}

Color _rankAccent(String rankKey) {
  if (rankKey.startsWith('silver')) return const Color(0xFFBFD6E5);
  if (rankKey.startsWith('gold')) return const Color(0xFFF1C45E);
  if (rankKey.startsWith('platinum')) return const Color(0xFF58D5E7);
  if (rankKey.startsWith('master')) return const Color(0xFFC58BFF);
  return const Color(0xFFD78A53);
}
