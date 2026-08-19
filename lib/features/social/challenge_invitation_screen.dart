import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/rank_identity_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/rank_emblem.dart';
import '../duel/pre_match_ready_screen.dart';

class ChallengeInvitationScreen extends StatefulWidget {
  const ChallengeInvitationScreen({super.key, required this.challengeId});

  final String challengeId;

  @override
  State<ChallengeInvitationScreen> createState() =>
      _ChallengeInvitationScreenState();
}

class _ChallengeInvitationScreenState extends State<ChallengeInvitationScreen> {
  final SocialApiClient _social = SocialApiClient.instance;
  final EconomyService _economy = EconomyService.instance;

  SocialChallenge? _challenge;
  PublicRankSummary? _challengerRank;
  Timer? _countdown;
  String? _error;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_refresh);
    unawaited(_economy.initialize());
    unawaited(_load());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _economy.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  int get _secondsLeft {
    final challenge = _challenge;
    if (challenge == null) return 0;
    return challenge.expiresAt
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 86400)
        .toInt();
  }

  bool get _expired =>
      _challenge != null &&
      (_challenge!.status != 'pending' || _secondsLeft <= 0);

  Future<void> _load() async {
    _countdown?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _challengerRank = null;
      });
    }

    try {
      final pending = await _social.loadPendingChallenges();
      SocialChallenge? found;
      for (final challenge in pending) {
        if (challenge.id == widget.challengeId) {
          found = challenge;
          break;
        }
      }
      if (!mounted) return;
      if (found == null) {
        setState(() {
          _challenge = null;
          _error = context.tr('challenge_timed_out');
        });
        return;
      }
      setState(() => _challenge = found);
      unawaited(_loadChallengerRank(found.challenger.publicId));
      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_secondsLeft <= 0) _countdown?.cancel();
        setState(() {});
      });
    } on SocialApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('try_again_when_connected'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChallengerRank(String publicId) async {
    try {
      final rank = await RankIdentityService.instance.loadPublicRankSummary(
        publicId,
      );
      if (!mounted || _challenge?.challenger.publicId != publicId) return;
      setState(() => _challengerRank = rank);
    } catch (_) {
      // A private or temporarily unavailable profile stays hidden. Never fall
      // back to the legacy SocialPlayer.rating because that is hidden MMR.
    }
  }

  Future<void> _respond({required bool accept}) async {
    final challenge = _challenge;
    if (challenge == null || _processing || _expired) return;
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final response = await _social.respondToChallenge(
        challengeId: challenge.id,
        accept: accept,
      );
      if (!mounted) return;

      if (!accept) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('challenge_declined'))),
        );
        Navigator.of(context).pop();
        return;
      }

      final roomId = response.roomId;
      if (roomId == null || roomId.isEmpty) {
        setState(() => _error = context.tr('matchmaking_start_failed'));
        return;
      }
      await _economy.refresh(showLoading: false);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),
      );
    } on SocialApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('matchmaking_start_failed'));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
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
              constraints: const BoxConstraints(maxWidth: 620),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF29D398),
                      ),
                    )
                  : _challenge == null
                  ? _UnavailableChallenge(
                      message: _error ?? context.tr('challenge_timed_out'),
                      onRetry: _load,
                      onClose: () => Navigator.of(context).pop(),
                    )
                  : _ChallengeCard(
                      challenge: _challenge!,
                      challengerRank: _challengerRank,
                      secondsLeft: _secondsLeft,
                      expired: _expired,
                      processing: _processing,
                      error: _error,
                      balance: _economy.balance,
                      entryFee: _economy.entryFeeForDifficulty(
                        _challenge!.difficulty,
                      ),
                      winnerPot: _economy.winnerPotForDifficulty(
                        _challenge!.difficulty,
                      ),
                      canAccept: _economy.canEnterOnline,
                      onAccept: () => _respond(accept: true),
                      onDecline: () => _respond(accept: false),
                      onRetry: _load,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.challengerRank,
    required this.secondsLeft,
    required this.expired,
    required this.processing,
    required this.error,
    required this.balance,
    required this.entryFee,
    required this.winnerPot,
    required this.canAccept,
    required this.onAccept,
    required this.onDecline,
    required this.onRetry,
  });

  final SocialChallenge challenge;
  final PublicRankSummary? challengerRank;
  final int secondsLeft;
  final bool expired;
  final bool processing;
  final String? error;
  final int balance;
  final int entryFee;
  final int winnerPot;
  final bool canAccept;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final difficulty = _difficulty(challenge.difficulty);
    final accent = _accent(difficulty);
    final rank = challengerRank;
    final avatarKey = rank?.avatarKey ?? 'challenge-${challenge.challenger.publicId}';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        InPageHeader(title: context.tr('challenge')),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: .24),
                const Color(0xFF111C20).withValues(alpha: .97),
                const Color(0xFF071014),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: accent.withValues(alpha: .48)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .32),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            children: [
              _StatusChip(
                expired: expired,
                secondsLeft: secondsLeft,
                accent: accent,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: .10),
                      border: Border.all(color: accent.withValues(alpha: .32)),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: .14),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                    child: PlayerAvatar(
                      displayName: challenge.challenger.displayName,
                      avatarKey: avatarKey,
                      radius: 44,
                    ),
                  ),
                  if (rank != null) ...[
                    const SizedBox(width: 12),
                    RankEmblem(rankKey: rank.rankKey, size: 74),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Text(
                challenge.challenger.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@${challenge.challenger.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .56),
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (rank != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${rank.rankName} · ${rank.rankPoints} RP',
                  style: const TextStyle(
                    color: Color(0xFF8ED8FF),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                context.tr('wants_to_play_again', <Object>[
                  challenge.challenger.displayName,
                ]),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .78),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      asset: DuelAsset.grid,
                      label: context.strings.difficultyLabel(difficulty),
                      value: '${difficulty.index + 1}/5',
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Metric(
                      asset: DuelAsset.trophy,
                      label: 'RP',
                      value: rank == null ? '—' : '${rank.rankPoints}',
                      color: const Color(0xFFFFC94D),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Metric(
                      asset: DuelAsset.target,
                      label: context.tr('time'),
                      value: _time(secondsLeft),
                      color: const Color(0xFF3AA9FF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _EconomyBar(
                balance: balance,
                entryFee: entryFee,
                winnerPot: winnerPot,
              ),
              if (!canAccept && !expired) ...[
                const SizedBox(height: 12),
                _InlineError(
                  message: context.tr('not_enough_coins_online', <Object>[
                    entryFee,
                  ]),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: error!, onRetry: onRetry),
              ],
              const SizedBox(height: 20),
              if (expired)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(context.tr('try_again')),
                  ),
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: processing || !canAccept ? null : onAccept,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: accent,
                      foregroundColor: const Color(0xFF071014),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    icon: processing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt_rounded),
                    label: Text(context.tr('accept')),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: processing ? null : onDecline,
                    child: Text(context.tr('decline')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.expired,
    required this.secondsLeft,
    required this.accent,
  });

  final bool expired;
  final int secondsLeft;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = expired ? const Color(0xFFFF5C7A) : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            expired ? Icons.timer_off_outlined : Icons.bolt_rounded,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 6),
          Text(
            expired ? context.tr('challenge_timed_out') : _time(secondsLeft),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.asset,
    required this.label,
    required this.value,
    required this.color,
  });

  final String asset;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Column(
        children: [
          DuelAssetIcon(asset, size: 21, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .52),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EconomyBar extends StatelessWidget {
  const _EconomyBar({
    required this.balance,
    required this.entryFee,
    required this.winnerPot,
  });

  final int balance;
  final int entryFee;
  final int winnerPot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .24),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _CoinStat(
              label: context.tr('current_balance'),
              value: balance,
            ),
          ),
          Expanded(
            child: _CoinStat(label: context.tr('entry_fee'), value: entryFee),
          ),
          Expanded(
            child: _CoinStat(label: context.tr('winner_pot'), value: winnerPot),
          ),
        ],
      ),
    );
  }
}

class _CoinStat extends StatelessWidget {
  const _CoinStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DuelAssetIcon(
              DuelAsset.coin,
              size: 15,
              color: Color(0xFFFFC94D),
            ),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .48),
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 7, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5C7A).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFFFF5C7A).withValues(alpha: .26),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF8FA3),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onRetry != null)
            IconButton(
              tooltip: context.tr('try_again'),
              onPressed: onRetry,
              icon: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
        ],
      ),
    );
  }
}

class _UnavailableChallenge extends StatelessWidget {
  const _UnavailableChallenge({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        InPageHeader(title: context.tr('challenge')),
        const SizedBox(height: 52),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF071014).withValues(alpha: .88),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: const Color(0xFFFF5C7A).withValues(alpha: .28),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.timer_off_outlined,
                color: Color(0xFFFF8FA3),
                size: 48,
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('challenge_timed_out'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: .64)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.tr('try_again')),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onClose,
                  child: Text(context.tr('main_menu')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

SudokuDifficulty _difficulty(String value) {
  for (final difficulty in SudokuDifficulty.values) {
    if (difficulty.name == value.toLowerCase()) return difficulty;
  }
  return SudokuDifficulty.easy;
}

Color _accent(SudokuDifficulty difficulty) => switch (difficulty) {
  SudokuDifficulty.beginner => const Color(0xFF29D398),
  SudokuDifficulty.easy => const Color(0xFF3AA9FF),
  SudokuDifficulty.medium => const Color(0xFFFFC94D),
  SudokuDifficulty.hard => const Color(0xFFFF8A3D),
  SudokuDifficulty.expert => const Color(0xFFFF5C7A),
};

String _time(int seconds) {
  final safe = seconds.clamp(0, 86400).toInt();
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}
