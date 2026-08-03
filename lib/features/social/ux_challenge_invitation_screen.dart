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
import '../economy/coin_store_screen.dart';

class UxChallengeInvitationScreen extends StatefulWidget {
  const UxChallengeInvitationScreen({
    super.key,
    required this.challengeId,
  });

  final String challengeId;

  @override
  State<UxChallengeInvitationScreen> createState() =>
      _UxChallengeInvitationScreenState();
}

class _UxChallengeInvitationScreenState
    extends State<UxChallengeInvitationScreen> {
  final SocialApiClient _social = SocialApiClient.instance;
  final EconomyService _economy = EconomyService.instance;
  SocialChallenge? _challenge;
  Timer? _timer;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _economy.addListener(_refresh);
    unawaited(_economy.initialize());
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
        .clamp(0, 86400);
  }

  int get _entryFee => _economy.entryFeeForDifficulty(
    _challenge?.difficulty ?? 'beginner',
  );

  bool get _expired =>
      _challenge == null ||
      _challenge!.status != 'pending' ||
      _secondsLeft <= 0;

  bool get _canAccept => !_expired && _economy.balance >= _entryFee;

  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _economy.refresh(showLoading: false);
      final pending = await _social.loadPendingChallenges();
      SocialChallenge? match;
      for (final challenge in pending) {
        if (challenge.id == widget.challengeId) {
          match = challenge;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _challenge = match;
        if (match == null) _error = context.tr('challenge_timed_out');
      });
      if (match != null) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          if (_secondsLeft <= 0) _timer?.cancel();
          setState(() {});
        });
      }
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
    if (challenge == null || _busy || _expired) return;
    if (accept && !_canAccept) {
      await _openStore();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _social.respondToChallenge(
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
      final roomId = result.roomId;
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openStore() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CoinStoreScreen()),
    );
    await _economy.refresh(showLoading: false);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(context.tr('challenge')),
      ),
      body: AppBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _challenge == null
                  ? _Unavailable(
                      message: _error ?? context.tr('challenge_timed_out'),
                      onRetry: _load,
                    )
                  : _content(_challenge!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(SocialChallenge challenge) {
    final difficulty = SudokuDifficulty.values.firstWhere(
      (value) => value.name == challenge.difficulty,
      orElse: () => SudokuDifficulty.easy,
    );
    final accent = _accent(difficulty);
    final missing = (_entryFee - _economy.balance).clamp(0, _entryFee);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          color: const Color(0xFF101B20).withValues(alpha: .96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: accent.withValues(alpha: .5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Chip(
                  avatar: Icon(
                    _expired ? Icons.timer_off_outlined : Icons.timer_outlined,
                    color: _expired ? Colors.redAccent : accent,
                  ),
                  label: Text(
                    _expired
                        ? context.tr('challenge_timed_out')
                        : '${_secondsLeft}s',
                  ),
                ),
                const SizedBox(height: 18),
                PlayerAvatar(
                  displayName: challenge.challenger.displayName,
                  avatarKey: 'challenge-${challenge.challenger.publicId}',
                  radius: 48,
                  semanticLabel: context.tr(
                    'player_avatar_semantics',
                    <Object>[challenge.challenger.displayName],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  challenge.challenger.displayName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '@${challenge.challenger.username}',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('wants_to_play_again', <Object>[
                    challenge.challenger.displayName,
                  ]),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .76),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Metric(
                      icon: Icons.grid_4x4_rounded,
                      label: context.strings.difficultyLabel(difficulty),
                      color: accent,
                    ),
                    _Metric(
                      icon: Icons.emoji_events_outlined,
                      label: context.tr('rating_value', <Object>[
                        challenge.challenger.rating,
                      ]),
                      color: const Color(0xFFFFC94D),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Card(
                  color: Colors.black.withValues(alpha: .22),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact =
                            constraints.maxWidth < 440 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3;
                        final itemWidth = compact
                            ? (constraints.maxWidth - 8) / 2
                            : constraints.maxWidth / 3;
                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: compact ? 8 : 0,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: itemWidth,
                              child: _CoinValue(
                                label: context.tr('current_balance'),
                                value: _economy.balance,
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: _CoinValue(
                                label: context.tr('entry_fee'),
                                value: _entryFee,
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: _CoinValue(
                                label: context.tr('winner_pot'),
                                value: _entryFee * 2,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (!_canAccept && !_expired) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(
                        context.tr('not_enough_coins_online', <Object>[
                          _entryFee,
                        ]),
                      ),
                      subtitle: Text(
                        '${context.tr('coin_amount', <Object>[missing])} · ${context.tr('open_coin_store')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openStore,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || !_canAccept
                        ? null
                        : () => _respond(true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: accent,
                      foregroundColor: const Color(0xFF071014),
                    ),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt_rounded),
                    label: Text(
                      context.tr('accept'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy || _expired ? null : () => _respond(false),
                  child: Text(context.tr('decline')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DuelAssetIcon(DuelAsset.timer, size: 50),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.tr('try_again')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: 48,
        maxWidth: MediaQuery.sizeOf(context).width - 72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
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
      mainAxisSize: MainAxisSize.min,
      children: [
        const DuelAssetIcon(
          DuelAsset.coin,
          size: 18,
          color: Color(0xFFFFC94D),
        ),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .58),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

Color _accent(SudokuDifficulty difficulty) {
  return switch (difficulty) {
    SudokuDifficulty.beginner => const Color(0xFF29D398),
    SudokuDifficulty.easy => const Color(0xFF3AA9FF),
    SudokuDifficulty.medium => const Color(0xFFFFC94D),
    SudokuDifficulty.hard => const Color(0xFFFF8A3D),
    SudokuDifficulty.expert => const Color(0xFFFF5C7A),
  };
}
