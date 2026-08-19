import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../models/rank_identity_models.dart';
import '../../services/rank_identity_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/player_avatar.dart';

/// Player-facing competitive ladder.
///
/// The existing 1000-based Elo remains an internal matchmaking/MMR signal.
/// This screen intentionally exposes only Rank Points (RP).
class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen> {
  RankIdentityProfile? _profile;
  RankLeaderboardSnapshot? _board;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        RankIdentityService.instance.refresh(),
        RankIdentityService.instance.loadLeaderboard(limit: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as RankIdentityProfile;
        _board = results[1] as RankLeaderboardSnapshot;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading && _profile == null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 220),
                          Center(child: CircularProgressIndicator()),
                        ],
                      )
                    : _content(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final profile = _profile;
    final board = _board;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 34),
      children: [
        InPageHeader(
          title: 'Ranked ladder',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          _MessageCard(message: _error!, onRetry: _load),
        ],
        if (profile != null) ...[
          const SizedBox(height: 8),
          _CurrentRankCard(
            profile: profile,
            leaderboardRank: board?.currentRank,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: 'Rank progression',
            subtitle:
                'Each division is 300 RP. Earned rank frames remain permanently available.',
          ),
          const SizedBox(height: 10),
          _RankRoadmap(profile: profile),
        ],
        const SizedBox(height: 20),
        const _SectionTitle(
          title: 'Global RP leaderboard',
          subtitle:
              'Visible RP determines your displayed rank. Matchmaking skill stays hidden.',
        ),
        const SizedBox(height: 10),
        if (board == null && _loading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (board == null || board.entries.isEmpty)
          const _EmptyBoard()
        else
          _LeaderboardList(
            snapshot: board,
            currentPublicId: profile?.publicId,
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .56),
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CurrentRankCard extends StatelessWidget {
  const _CurrentRankCard({required this.profile, this.leaderboardRank});

  final RankIdentityProfile profile;
  final int? leaderboardRank;

  @override
  Widget build(BuildContext context) {
    final globalRank = leaderboardRank == null ? '—' : '#$leaderboardRank';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              PlayerAvatar(
                displayName: profile.displayName,
                avatarKey: profile.avatarKey,
                radius: 39,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.rankName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${profile.rankPoints} RP',
                      style: const TextStyle(
                        color: Color(0xFF66C7FF),
                        fontSize: 28,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              _GlobalRankPill(label: globalRank),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: profile.progress.clamp(0.0, 1.0).toDouble(),
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: .08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF66C7FF),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                profile.divisionSize == null
                    ? '${profile.pointsInDivision} RP above Master I'
                    : '${profile.pointsInDivision}/${profile.divisionSize} RP',
                style: _smallMuted(),
              ),
              const Spacer(),
              Text(
                profile.nextRankName == null
                    ? 'Top rank'
                    : '${profile.pointsToNext ?? 0} RP to ${profile.nextRankName}',
                style: _smallMuted(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _smallMuted() => TextStyle(
        color: Colors.white.withValues(alpha: .58),
        fontSize: 11,
        fontWeight: FontWeight.w800,
      );
}

class _GlobalRankPill extends StatelessWidget {
  const _GlobalRankPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF66C7FF).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF66C7FF).withValues(alpha: .20),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'GLOBAL',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .45),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRoadmap extends StatelessWidget {
  const _RankRoadmap({required this.profile});

  final RankIdentityProfile profile;

  @override
  Widget build(BuildContext context) {
    final rewards = <String, RankRewardState>{
      for (final reward in profile.rankRewards) reward.rankKey: reward,
    };
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rankTierCatalog.length; i++) ...[
            _TierRow(
              tier: rankTierCatalog[i],
              reward: rewards[rankTierCatalog[i].key],
              current: profile.rankKey == rankTierCatalog[i].key,
              unlocked: profile.unlockedFrameKeys.contains(
                rankTierCatalog[i].key,
              ),
              previewIndex: i,
            ),
            if (i != rankTierCatalog.length - 1)
              Divider(
                height: 1,
                indent: 74,
                color: Colors.white.withValues(alpha: .055),
              ),
          ],
        ],
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.reward,
    required this.current,
    required this.unlocked,
    required this.previewIndex,
  });

  final RankTierInfo tier;
  final RankRewardState? reward;
  final bool current;
  final bool unlocked;
  final int previewIndex;

  @override
  Widget build(BuildContext context) {
    final avatarNumber = ((previewIndex * 7) % 96) + 1;
    final previewKey = RankIdentityKey(
      avatarKey: 'preset_${avatarNumber.toString().padLeft(3, '0')}',
      frameKey: tier.key,
    ).encode();
    final rewardCoins = reward?.amount ?? 0;
    return Container(
      color: current
          ? const Color(0xFF66C7FF).withValues(alpha: .075)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          PlayerAvatar(
            displayName: tier.label,
            avatarKey: previewKey,
            radius: 25,
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
                        tier.label,
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
                      const _StatusPill(label: 'CURRENT'),
                    ] else if (unlocked) ...[
                      const SizedBox(width: 7),
                      const _StatusPill(label: 'UNLOCKED'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  tier.minPoints == 0
                      ? 'Starts at 0 RP'
                      : 'Unlocks at ${tier.minPoints} RP',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .50),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (tier.minPoints == 0)
            const _RewardPill(label: 'START', claimed: true, neutral: true)
          else
            _RewardPill(
              label: '+$rewardCoins Coin',
              claimed: reward?.claimed == true,
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF66C7FF).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF66C7FF).withValues(alpha: .18),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF8ED8FF),
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .35,
        ),
      ),
    );
  }
}

class _RewardPill extends StatelessWidget {
  const _RewardPill({
    required this.label,
    required this.claimed,
    this.neutral = false,
  });

  final String label;
  final bool claimed;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final color = neutral
        ? const Color(0xFF8EA2AD)
        : claimed
        ? const Color(0xFF29D398)
        : const Color(0xFFFFC94D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            claimed ? Icons.check_circle_rounded : Icons.monetization_on_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({
    required this.snapshot,
    required this.currentPublicId,
  });

  final RankLeaderboardSnapshot snapshot;
  final String? currentPublicId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < snapshot.entries.length; i++) ...[
            _LeaderboardRow(
              entry: snapshot.entries[i],
              isCurrent: snapshot.entries[i].publicId == currentPublicId,
            ),
            if (i != snapshot.entries.length - 1)
              Divider(
                height: 1,
                indent: 62,
                color: Colors.white.withValues(alpha: .055),
              ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.isCurrent});

  final RankLeaderboardEntry entry;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final winRate = (entry.winRate * 100).round();
    return Container(
      color: isCurrent
          ? const Color(0xFF66C7FF).withValues(alpha: .07)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '#${entry.rank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: entry.rank <= 3
                    ? const Color(0xFFFFC94D)
                    : Colors.white.withValues(alpha: .62),
                fontSize: entry.rank <= 3 ? 16 : 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          PlayerAvatar(
            displayName: entry.displayName,
            avatarKey: entry.avatarKey,
            radius: 22,
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
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      const _StatusPill(label: 'YOU'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.rankName} · ${entry.gamesPlayed} games · $winRate% wins',
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
          const SizedBox(width: 10),
          Text(
            '${entry.rankPoints} RP',
            style: const TextStyle(
              color: Color(0xFF66C7FF),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.leaderboard_rounded,
            color: Color(0xFF66C7FF),
            size: 36,
          ),
          const SizedBox(height: 10),
          const Text(
            'No RP leaderboard entries yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Complete ranked online matches to climb from Bronze III.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .54),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8A3D).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF8A3D).withValues(alpha: .25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFFFB37A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Retry',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
