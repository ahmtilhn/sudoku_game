import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../models/rank_identity_fallback.dart';
import '../../models/rank_identity_models.dart';
import '../../services/rank_identity_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/in_page_header.dart';
import '../social/profile_customization_screen.dart';
import '../social/rank_identity_summary_card.dart';
import 'leaderboards_screen.dart';

class RankedProgressScreen extends StatefulWidget {
  const RankedProgressScreen({super.key});

  @override
  State<RankedProgressScreen> createState() => _RankedProgressScreenState();
}

class _RankedProgressScreenState extends State<RankedProgressScreen> {
  late RankIdentityProfile _profile;
  bool _loading = false;
  bool _serverReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cached = RankIdentityService.instance.current.value;
    _profile = cached ?? buildRankIdentityFallback();
    _serverReady = cached != null;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await RankIdentityService.instance.refresh();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _serverReady = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverReady = false;
        _error = UserSafeError.message(context, error);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCustomization() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ProfileCustomizationScreen()),
    );
    if (mounted) await _refresh();
  }

  Future<void> _openLeaderboards() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const LeaderboardsScreen()));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InPageHeader(
                      title: context.tr('ranked_progress_title'),
                      actions: [
                        IconButton.filledTonal(
                          tooltip: context.tr('leaderboards'),
                          onPressed: _loading ? null : _openLeaderboards,
                          icon: const Icon(Icons.emoji_events_rounded),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: context.tr('refresh'),
                          onPressed: _loading ? null : _refresh,
                          icon: _loading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    if (!_serverReady && _error != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC73D).withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFFFFC73D,
                            ).withValues(alpha: .22),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              color: Color(0xFFFFC73D),
                              size: 20,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .72),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4, bottom: 18),
                          children: [
                            RankIdentitySummaryCard(
                              profile: _profile,
                              onCustomize: _openCustomization,
                            ),
                            const SizedBox(height: 12),
                            _RankedPurposeCard(profile: _profile),
                          ],
                        ),
                      ),
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

class _RankedPurposeCard extends StatelessWidget {
  const _RankedPurposeCard({required this.profile});

  final RankIdentityProfile profile;

  @override
  Widget build(BuildContext context) {
    final next = profile.nextRankName;
    final message = next == null
        ? context.tr('ranked_top_division_body')
        : context.tr('ranked_next_division_body', <Object>[
            profile.pointsToNext ?? 0,
            next,
          ]);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.trending_up_rounded,
            color: Color(0xFF66C7FF),
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('competitive_progression'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .62),
                    fontSize: 12,
                    height: 1.35,
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
