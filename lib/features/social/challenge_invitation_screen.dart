import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';
import '../duel/online_duel_screen.dart';

class ChallengeInvitationScreen extends StatefulWidget {
  const ChallengeInvitationScreen({
    super.key,
    required this.challengeId,
  });

  final String challengeId;

  @override
  State<ChallengeInvitationScreen> createState() =>
      _ChallengeInvitationScreenState();
}

class _ChallengeInvitationScreenState
    extends State<ChallengeInvitationScreen> {
  final SocialApiClient _social = SocialApiClient.instance;
  final EconomyService _economy = EconomyService.instance;

  Timer? _timer;
  SocialChallenge? _challenge;
  String? _error;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_onEconomyChanged);
    unawaited(_economy.initialize());
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  int get _remainingSeconds {
    final challenge = _challenge;
    if (challenge == null) return 0;
    return challenge.expiresAt.difference(DateTime.now()).inSeconds.clamp(
      0,
      86400,
    );
  }

  bool get _expired {
    final challenge = _challenge;
    return challenge != null &&
        (challenge.status != 'pending' || _remainingSeconds <= 0);
  }

  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final challenges = await _social.loadPendingChallenges();
      SocialChallenge? selected;
      for (final challenge in challenges) {
        if (challenge.id == widget.challengeId) {
          selected = challenge;
          break;
        }
      }

      if (!mounted) return;
      if (selected == null) {
        setState(() {
          _challenge = null;
          _error = context.tr('challenge_timed_out');
        });
        return;
      }

      setState(() => _challenge = selected);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_remainingSeconds <= 0) {
          _timer?.cancel();
        }
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

  Future<void> _respond(bool accept) async {
    final challenge = _challenge;
    if (challenge == null || _processing || _expired) return;

    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final updated = await _social.respondToChallenge(
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

      final roomId = updated.roomId;
      if (roomId == null || roomId.isEmpty) {
        setState(() => _error = context.tr('matchmaking_start_failed'));
        return;
      }

      await _economy.refresh(showLoading: false);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(builder: (_) => OnlineDuelScreen(roomId: roomId)),
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.tr('challenge')),
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _loading
                    ? const Center(
                        key: ValueKey('loading'),
                        child: CircularProgressIndicator(
                          color: Color(0xFF29D398),
                        ),
                      )
                    : _challenge == null
                    ? _ChallengeUnavailable(
                        key: const ValueKey('unavailable'),
                        message:
                            _error ?? context.tr('challenge_timed_out'),
                        onRetry: _load,
                        onClose: () => Navigator.of(context).pop(),
                      )
                    : _ChallengeInvitationCard(
                        key: ValueKey(_challenge!.id),
                        challenge: _challenge!,
                        remainingSeconds: _remainingSeconds,
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
                        onAccept: () => _respond(true),
                        onDecline: () => _respond(false),
                        onRetry: _load,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChallengeInvitationCard extends StatelessWidget {
  const _ChallengeInvitationCard({
    super.key,
    required this.challenge,
    required this.remainingSeconds,
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
  final int remainingSeconds;
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
    final difficulty = _parseDifficulty(challenge.difficulty);
    final accent = _difficultyAccent(difficulty);
    final timeLabel = _formatCountdown(remainingSeconds);

    return SingleChildScrollView(
      key: key,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: .24),
                  const Color(0xFF111C20).withValues(alpha: .96),
                  const Color(0xFF071014).withValues(alpha: .98),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: accent.withValues(alpha: .46)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .32),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                children: [
                  _InvitationStatusPill(
                    expired: expired,
                    remainingSeconds: remainingSeconds,
                    accent: accent,
                  ),
                  const SizedBox(height: 20),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: .10),
                          border: Border.all(
                            color: accent.withValues(alpha: .30),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: .12),
                              blurRadius: 30,
                            ),
                          ],
                        ),
                        child: const SizedBox.square(dimension: 112),
                      ),
                      PlayerAvatar(
                        displayName: challenge.challenger.displayName,
                        avatarKey:
                            'challenge-${challenge.challenger.publicId}',
                        radius: 48,
                        semanticLabel: context.tr(
                          'player_avatar_semantics',
                          <Object>[challenge.challenger.displayName],
                        ),
                      ),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.tr('wants_to_play_again', <Object>[
                      challenge.challenger.displayName,
                    ]),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .78),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _InvitationMetric(
                          asset: DuelAsset.grid,
                          label: context.strings.difficultyLabel(difficulty),
                          value: '${difficulty.index + 1}/5',
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _InvitationMetric(
                          asset: DuelAsset.trophy,
                          label: context.tr('rating'),
                          value: '${challenge.challenger.rating}',
                          color: const Color(0xFFFFC94D),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _InvitationMetric(
                          asset: DuelAsset.target,
                          label: context.tr('time'),
                          value: timeLabel,
                          color: const Color(0xFF3AA9FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _EconomySummary(
                    balance: balance,
                    entryFee: entryFee,
                    winnerPot: winnerPot,
                  ),
                  if (!canAccept && !expired) ...[
                    const SizedBox(height: 12),
                    _InlineWarning(
                      message: context.tr('not_enough_coins_online', <Object>[
                        entryFee,
                      ]),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    _InlineWarning(message: error!, retry: onRetry),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(Icons.bolt_rounded),
                        label: Text(context.tr('accept')),
                      ),
                    ),
                    const SizedBox(height: 7),
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
          ),
        ],
      ),
    );
  }
}

class _InvitationStatusPill extends StatelessWidget {
  const _InvitationStatusPill({
    required this.expired,
    required this.remainingSeconds,
    required this.accent,
  });

  final bool expired;
  final int remainingSeconds;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = expired ? const Color(0xFFFF5C7A) : accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .34)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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
              expired
                  ? context.tr('challenge_timed_out')
                  : _formatCountdown(remainingSeconds),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationMetric extends StatelessWidget {
  const _InvitationMetric({
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
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
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
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
      ),
    );
  }
}

class _EconomySummary extends StatelessWidget {
  const _EconomySummary({
    required this.balance,
    required this.entryFee,
    required this.winnerPot,
  });

  final int balance;
  final int entryFee;
  final int winnerPot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF071014).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Expanded(
              child: _CoinValue(
                label: context.tr('current_balance'),
                value: balance,
              ),
            ),
            Container(
              width: 1,
              height: 38,
              color: Colors.white.withValues(alpha: .08),
            ),
            Expanded(
              child: _CoinValue(
                label: context.tr('entry_fee'),
                value: entryFee,
              ),
            ),
            Container(
              width: 1,
              height: 38,
              color: Colors.white.withValues(alpha: .08),
            ),
            Expanded(
              child: _CoinValue(
                label: context.tr('winner_pot'),
                value: winnerPot,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinValue extends StatelessWidget {
  const _CoinValue({required this.label, required this.value});

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
            Flexible(
              child: Text(
                '$value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
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

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message, this.retry});

  final String message;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFF5C7A).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFFFF5C7A).withValues(alpha: .26),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 9, 7, 9),
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
            if (retry != null)
              IconButton(
                tooltip: context.tr('try_again'),
                onPressed: retry,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChallengeUnavailable extends StatelessWidget {
  const _ChallengeUnavailable({
    super.key,
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
      key: key,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 28),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF071014).withValues(alpha: .88),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: const Color(0xFFFF5C7A).withValues(alpha: .28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
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
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .64),
                    height: 1.35,
                  ),
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
        ),
      ],
    );
  }
}

SudokuDifficulty _parseDifficulty(String value) {
  for (final difficulty in SudokuDifficulty.values) {
    if (difficulty.name == value.toLowerCase()) return difficulty;
  }
  return SudokuDifficulty.easy;
}

Color _difficultyAccent(SudokuDifficulty difficulty) => switch (difficulty) {
  SudokuDifficulty.beginner => const Color(0xFF29D398),
  SudokuDifficulty.easy => const Color(0xFF3AA9FF),
  SudokuDifficulty.medium => const Color(0xFFFFC94D),
  SudokuDifficulty.hard => const Color(0xFFFF8A3D),
  SudokuDifficulty.expert => const Color(0xFFFF5C7A),
};

String _formatCountdown(int seconds) {
  final safeSeconds = seconds.clamp(0, 86400);
  final minutes = safeSeconds ~/ 60;
  final remainder = safeSeconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
