import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../models/country_catalog.dart';
import '../../models/rank_identity_fallback.dart';
import '../../models/rank_identity_models.dart';
import '../../services/rank_identity_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/player_avatar.dart';

/// Player-facing competitive ladder.
///
/// Hidden 1000-based Elo/MMR remains internal. This page only exposes visible
/// Rank Points (RP), and it always renders immediately even when the additive
/// rank backend is temporarily unavailable.
class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen> {
  late RankIdentityProfile _profile;
  RankLeaderboardSnapshot? _board;
  Map<String, String> _countryFlags = const <String, String>{};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profile =
        RankIdentityService.instance.current.value ??
        buildRankIdentityFallback();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    Object? firstError;
    RankIdentityProfile? loadedProfile;
    RankLeaderboardSnapshot? loadedBoard;
    Map<String, String>? loadedCountryFlags;

    await Future.wait<void>([
      () async {
        try {
          loadedProfile = await RankIdentityService.instance.refresh();
        } catch (error) {
          firstError ??= error;
        }
      }(),
      () async {
        try {
          // Player-facing in-app board. Hidden Elo/MMR is not returned here.
          loadedBoard = await RankIdentityService.instance.loadLeaderboard(
            limit: 100,
          );
        } catch (error) {
          firstError ??= error;
        }
      }(),
      () async {
        try {
          // Country is a voluntary profile decoration. It must never block the
          // competitive ladder when the preference endpoint is unavailable.
          loadedCountryFlags = await RankIdentityService.instance
              .loadRankCountryFlags(limit: 100);
        } catch (_) {
          // Leave flags empty and keep the RP ladder fully usable.
        }
      }(),
    ]);

    if (!mounted) return;
    setState(() {
      if (loadedProfile != null) _profile = loadedProfile!;
      if (loadedBoard != null) _board = loadedBoard;
      if (loadedCountryFlags != null) _countryFlags = loadedCountryFlags!;
      _loading = false;
      if (firstError != null) {
        _error = UserSafeError.message(context, firstError!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 34),
                  children: [
                    InPageHeader(
                      title: context.tr('ranked_ladder'),
                      actions: [
                        IconButton(
                          tooltip: context.tr('refresh'),
                          onPressed: _loading ? null : _load,
                          icon: _loading
                              ? const SizedBox.square(
                                  dimension: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      _ConnectionNotice(
                        message: _error!,
                        busy: _loading,
                        onRetry: _load,
                      ),
                    ],
                    const SizedBox(height: 8),
                    _CurrentRankCard(
                      profile: _profile,
                      leaderboardRank: _board?.currentRank,
                    ),
                    const SizedBox(height: 14),
                    const _RankInfoCard(),
                    const SizedBox(height: 14),
                    _LeaderboardSectionTitle(
                      title: context.tr('global_rp_leaderboard'),
                    ),
                    const SizedBox(height: 10),
                    if (_board == null && _loading)
                      const _BoardLoadingCard()
                    else if (_board == null || _board!.entries.isEmpty)
                      _EmptyBoard(offline: _error != null)
                    else
                      _LeaderboardList(
                        snapshot: _board!,
                        currentPublicId: _profile.publicId,
                        countryFlags: _countryFlags,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _rankAccent(String rankKey) {
  final key = rankKey.toLowerCase();
  if (key.startsWith('silver')) return const Color(0xFFB9CAD8);
  if (key.startsWith('gold')) return const Color(0xFFFFC84D);
  if (key.startsWith('platinum')) return const Color(0xFF63DCF3);
  if (key.startsWith('master')) return const Color(0xFFC587FF);
  return const Color(0xFFE49555);
}

class _CurrentRankCard extends StatelessWidget {
  const _CurrentRankCard({required this.profile, this.leaderboardRank});

  final RankIdentityProfile profile;
  final int? leaderboardRank;

  @override
  Widget build(BuildContext context) {
    final accent = _rankAccent(profile.rankKey);
    final globalRank = leaderboardRank == null ? '—' : '#$leaderboardRank';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        final avatarRadius = compact ? 39.0 : 45.0;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: .13),
                const Color(0xFF111D23).withValues(alpha: .94),
                const Color(0xFF091218).withValues(alpha: .96),
              ],
              stops: const [0, .38, 1],
            ),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: accent.withValues(alpha: .58), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .12),
                blurRadius: 26,
                spreadRadius: -8,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .28),
                blurRadius: 24,
                offset: const Offset(0, 13),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -54,
                top: -64,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .10),
                        blurRadius: 70,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 13 : 16,
                  15,
                  compact ? 13 : 16,
                  14,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: .18),
                                blurRadius: 22,
                                spreadRadius: -4,
                              ),
                            ],
                          ),
                          child: PlayerAvatar(
                            displayName: profile.displayName,
                            avatarKey: profile.avatarKey,
                            radius: avatarRadius,
                          ),
                        ),
                        SizedBox(width: compact ? 11 : 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.rankName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 20 : 24,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${profile.rankPoints} RP',
                                style: const TextStyle(
                                  color: Color(0xFF66C7FF),
                                  fontSize: 31,
                                  height: 1,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _GlobalRankPill(label: globalRank, accent: accent),
                      ],
                    ),
                    const SizedBox(height: 15),
                    _PremiumProgressBar(
                      value: profile.progress.clamp(0.0, 1.0).toDouble(),
                      accent: accent,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          profile.divisionSize == null
                              ? '${profile.pointsInDivision} RP above Master I'
                              : '${profile.pointsInDivision}/${profile.divisionSize} RP',
                          style: _mutedRankStyle(),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            profile.nextRankName == null
                                ? 'Top rank'
                                : '${profile.pointsToNext ?? 0} RP to ${profile.nextRankName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: _mutedRankStyle(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  TextStyle _mutedRankStyle() => TextStyle(
    color: Colors.white.withValues(alpha: .62),
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );
}

class _PremiumProgressBar extends StatelessWidget {
  const _PremiumProgressBar({required this.value, required this.accent});

  final double value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Colors.white.withValues(alpha: .075),
            border: Border.all(color: Colors.white.withValues(alpha: .035)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ),
        Positioned(
          left: -1,
          child: _ProgressDiamond(accent: accent),
        ),
        Positioned(
          right: -1,
          child: _ProgressDiamond(accent: accent),
        ),
      ],
    );
  }
}

class _ProgressDiamond extends StatelessWidget {
  const _ProgressDiamond({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: .785398,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(1.5),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: .70), blurRadius: 7),
          ],
        ),
      ),
    );
  }
}

class _GlobalRankPill extends StatelessWidget {
  const _GlobalRankPill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: .17),
            Colors.black.withValues(alpha: .18),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .48)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .10),
            blurRadius: 14,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'GLOBAL',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .52),
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .9,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankInfoCard extends StatelessWidget {
  const _RankInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF071118).withValues(alpha: .58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF66C7FF).withValues(alpha: .13)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFB454).withValues(alpha: .08),
              border: Border.all(
                color: const Color(0xFFFFB454).withValues(alpha: .65),
              ),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: Color(0xFFFFC66B),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Visible RP determines your displayed rank. Matchmaking skill stays hidden.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .68),
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardSectionTitle extends StatelessWidget {
  const _LeaderboardSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final lineColor = const Color(0xFFE4A64C).withValues(alpha: .24);
    return Row(
      children: [
        Expanded(child: Divider(height: 1, color: lineColor)),
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(left: 7),
          transform: Matrix4.rotationZ(.785398),
          decoration: BoxDecoration(
            color: const Color(0xFFE4A64C).withValues(alpha: .65),
          ),
        ),
        Flexible(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .74),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(right: 7),
          transform: Matrix4.rotationZ(.785398),
          decoration: BoxDecoration(
            color: const Color(0xFFE4A64C).withValues(alpha: .65),
          ),
        ),
        Expanded(child: Divider(height: 1, color: lineColor)),
      ],
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({
    required this.snapshot,
    required this.currentPublicId,
    required this.countryFlags,
  });

  final RankLeaderboardSnapshot snapshot;
  final String currentPublicId;
  final Map<String, String> countryFlags;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < snapshot.entries.length; index++) ...[
          _LeaderboardRow(
            entry: snapshot.entries[index],
            current: snapshot.entries[index].publicId == currentPublicId,
            countryCode: countryFlags[snapshot.entries[index].publicId],
          ),
          if (index != snapshot.entries.length - 1)
            const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.entry,
    required this.current,
    this.countryCode,
  });

  final RankLeaderboardEntry entry;
  final bool current;
  final String? countryCode;

  @override
  Widget build(BuildContext context) {
    final flag = countryFlagEmoji(countryCode);
    final placementAccent = _placementAccent(entry.rank);
    final isPodium = entry.rank <= 3;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 11,
        vertical: isPodium ? 9 : 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: current
              ? [
                  const Color(0xFF087CC2).withValues(alpha: .18),
                  const Color(0xFF08141D).withValues(alpha: .76),
                ]
              : isPodium
              ? [
                  placementAccent.withValues(alpha: .10),
                  const Color(0xFF071118).withValues(alpha: .70),
                ]
              : [
                  const Color(0xFF071118).withValues(alpha: .48),
                  Colors.black.withValues(alpha: .16),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: current
              ? const Color(0xFF35B8FF).withValues(alpha: .86)
              : isPodium
              ? placementAccent.withValues(alpha: .48)
              : Colors.white.withValues(alpha: .055),
          width: current ? 1.2 : 1,
        ),
        boxShadow: [
          if (current)
            BoxShadow(
              color: const Color(0xFF35B8FF).withValues(alpha: .15),
              blurRadius: 17,
              spreadRadius: -5,
            )
          else if (isPodium)
            BoxShadow(
              color: placementAccent.withValues(alpha: .075),
              blurRadius: 14,
              spreadRadius: -7,
            ),
        ],
      ),
      child: Row(
        children: [
          _PlacementMark(rank: entry.rank),
          const SizedBox(width: 7),
          PlayerAvatar(
            displayName: entry.displayName,
            avatarKey: entry.avatarKey,
            radius: isPodium ? 24 : 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (flag.isNotEmpty) ...[
                      Text(
                        flag,
                        style: const TextStyle(fontSize: 16, height: 1),
                        semanticsLabel: 'Country flag',
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(width: 7),
                      const _YouBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.rankName} · ${(entry.winRate * 100).round()}% wins',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .48),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (entry.rank == 1) ...[
            const Icon(
              Icons.emoji_events_rounded,
              size: 16,
              color: Color(0xFFFFC94D),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '${entry.rankPoints} RP',
            style: TextStyle(
              color: entry.rank == 1
                  ? const Color(0xFFFFC94D)
                  : const Color(0xFF66C7FF),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlacementMark extends StatelessWidget {
  const _PlacementMark({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final asset = _placementAsset(rank);
    if (asset == null) {
      return SizedBox(
        width: 43,
        child: Center(
          child: Text(
            '$rank',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .70),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 43,
      height: 43,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Center(
          child: Text(
            '#$rank',
            style: TextStyle(
              color: _placementAccent(rank),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _YouBadge extends StatelessWidget {
  const _YouBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF35B8FF).withValues(alpha: .17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF35B8FF).withValues(alpha: .34),
        ),
      ),
      child: const Text(
        'YOU',
        style: TextStyle(
          color: Color(0xFF7ED6FF),
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

String? _placementAsset(int rank) => switch (rank) {
  1 => 'assets/ELO_rating_icons/elo_player_1.png',
  2 => 'assets/ELO_rating_icons/elo_player_2.png',
  3 => 'assets/ELO_rating_icons/elo_player_3.png',
  _ => null,
};

Color _placementAccent(int rank) => switch (rank) {
  1 => const Color(0xFFFFC94D),
  2 => const Color(0xFFC8DAE9),
  3 => const Color(0xFFDE854F),
  _ => const Color(0xFF66C7FF),
};

class _BoardLoadingCard extends StatelessWidget {
  const _BoardLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Loading player rankings…',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.leaderboard_rounded,
            color: const Color(0xFF66C7FF),
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            offline
                ? 'Leaderboard server is unavailable.'
                : 'No ranked players yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            offline
                ? 'Your current rank remains visible locally. Pull down or tap refresh after the backend reconnects.'
                : 'Complete a ranked duel to enter the RP leaderboard.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .52),
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice({
    required this.message,
    required this.busy,
    required this.onRetry,
  });

  final String message;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB454).withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFB454).withValues(alpha: .22),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFFFC66B),
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .72),
                fontSize: 11,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: context.tr('retry'),
            onPressed: busy ? null : onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}
