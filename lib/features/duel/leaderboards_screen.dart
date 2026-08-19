import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
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
        RankIdentityService.instance.current.value ?? buildRankIdentityFallback();
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
                      title: 'Ranked ladder',
                      actions: [
                        IconButton(
                          tooltip: 'Refresh',
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
                    const SizedBox(height: 20),
                    const _SectionTitle(
                      title: 'Global RP leaderboard',
                      subtitle:
                          'Visible RP determines your displayed rank. Matchmaking skill stays hidden.',
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                style: _mutedStyle(),
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
                  style: _mutedStyle(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _mutedStyle() => TextStyle(
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < snapshot.entries.length; index++) ...[
            _LeaderboardRow(
              entry: snapshot.entries[index],
              current: snapshot.entries[index].publicId == currentPublicId,
              countryCode: countryFlags[snapshot.entries[index].publicId],
            ),
            if (index != snapshot.entries.length - 1)
              Divider(
                height: 1,
                indent: 58,
                color: Colors.white.withValues(alpha: .055),
              ),
          ],
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: current
          ? const Color(0xFFB7A9FF).withValues(alpha: .07)
          : Colors.transparent,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '#${entry.rank}',
              style: TextStyle(
                color: entry.rank <= 3
                    ? const Color(0xFFFFD86A)
                    : Colors.white.withValues(alpha: .60),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          PlayerAvatar(
            displayName: entry.displayName,
            avatarKey: entry.avatarKey,
            radius: 22,
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
                    Expanded(
                      child: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${entry.rankName} · ${(entry.winRate * 100).round()}% wins',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .46),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${entry.rankPoints} RP',
            style: const TextStyle(
              color: Color(0xFF66C7FF),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

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
            tooltip: 'Retry',
            onPressed: busy ? null : onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}
