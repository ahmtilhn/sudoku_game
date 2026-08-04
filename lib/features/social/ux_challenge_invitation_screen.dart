import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';
import '../duel/pre_match_ready_screen.dart';
import '../economy/coin_store_screen.dart';

class UxChallengeInvitationScreen extends StatefulWidget {
  const UxChallengeInvitationScreen({super.key, required this.challengeId});

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
  int _statusTicks = 0;
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
        .clamp(0, 24 * 60 * 60);
  }

  int get _entryFee =>
      _economy.entryFeeForDifficulty(_challenge?.difficulty ?? 'beginner');

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
      final challenge = await _social.loadChallenge(widget.challengeId);
      if (!mounted) return;
      setState(() => _challenge = challenge);
      if (challenge.status == 'accepted') {
        final roomId = await _resolveRoomId(challenge);
        if (roomId != null && roomId.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_openRoom(roomId));
          });
        }
      } else if (challenge.status != 'pending') {
        setState(() => _error = _statusMessage(challenge.status));
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _statusTicks++;
        if (_secondsLeft <= 0) _timer?.cancel();
        setState(() {});
        if (_statusTicks.isEven) unawaited(_refreshStatus());
      });
    } on SocialApiException catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('try_again_when_connected'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshStatus() async {
    if (_busy || !mounted) return;
    try {
      final challenge = await _social.loadChallenge(widget.challengeId);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        if (challenge.status != 'pending' && challenge.status != 'accepted') {
          _error = _statusMessage(challenge.status);
        }
      });
      if (challenge.status == 'accepted') {
        final roomId = await _resolveRoomId(challenge);
        if (roomId != null && roomId.isNotEmpty) await _openRoom(roomId);
      }
    } catch (_) {
      // The explicit accept/decline actions still surface request failures.
    }
  }

  String _statusMessage(String status) {
    return switch (status) {
      'declined' => context.tr('challenge_declined'),
      'expired' => context.tr('challenge_timed_out'),
      'cancelled' => context.tr('cancel_search'),
      _ => context.tr('challenge_timed_out'),
    };
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

      final roomId = await _resolveRoomId(result);
      if (!mounted) return;
      if (roomId == null || roomId.isEmpty) {
        setState(() => _error = context.tr('matchmaking_start_failed'));
        return;
      }

      await _openRoom(roomId);
    } on SocialApiException catch (error) {
      if (accept && await _recoverAcceptedChallenge()) return;
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } catch (_) {
      if (accept && await _recoverAcceptedChallenge()) return;
      if (mounted) {
        setState(() => _error = context.tr('matchmaking_start_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _resolveRoomId(SocialChallenge result) async {
    final directRoomId = result.roomId?.trim();
    if (directRoomId != null && directRoomId.isNotEmpty) {
      return directRoomId;
    }

    for (var attempt = 0; attempt < 12; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final active = await _social.activeMatch();
      final activeChallengeId = active?['challengeId']?.toString();
      final roomId = active?['roomId']?.toString().trim();
      if (activeChallengeId == widget.challengeId &&
          roomId != null &&
          roomId.isNotEmpty) {
        return roomId;
      }
    }
    return null;
  }

  Future<bool> _recoverAcceptedChallenge() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        final active = await _social.activeMatch();
        final activeChallengeId = active?['challengeId']?.toString();
        final roomId = active?['roomId']?.toString().trim();
        if (activeChallengeId == widget.challengeId &&
            roomId != null &&
            roomId.isNotEmpty) {
          await _openRoom(roomId);
          return true;
        }
      } catch (_) {
        // The backend may still be completing or repairing the accepted room.
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<void> _openRoom(String roomId) async {
    _timer?.cancel();
    await _economy.refresh(showLoading: false);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),
    );
  }

  Future<void> _openStore() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const CoinStoreScreen()));
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
                  avatar: DuelAssetIcon(
                    _expired ? DuelAsset.close : DuelAsset.timer,
                    size: 19,
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
                  style: TextStyle(color: Colors.white.withValues(alpha: .76)),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Metric(
                      asset: DuelAsset.grid,
                      label: context.strings.difficultyLabel(difficulty),
                      color: accent,
                    ),
                    _Metric(
                      asset: DuelAsset.trophy,
                      label: context.tr('rating_value', <Object>[
                        challenge.challenger.rating,
                      ]),
                      color: const Color(0xFFFFC94D),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _EconomySummary(balance: _economy.balance, entryFee: _entryFee),
                if (!_canAccept && !_expired) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const DuelAssetIcon(DuelAsset.lock, size: 24),
                      title: Text(
                        context.tr('not_enough_coins_online', <Object>[
                          _entryFee,
                        ]),
                      ),
                      subtitle: Text(
                        '${context.tr('coin_amount', <Object>[missing])} · ${context.tr('open_coin_store')}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
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
                        : const DuelAssetIcon(DuelAsset.swords, size: 23),
                    label: Text(context.tr('accept')),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DuelAssetIcon(DuelAsset.timer, size: 54),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const DuelAssetIcon(DuelAsset.refresh, size: 20),
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
    required this.asset,
    required this.label,
    required this.color,
  });

  final String asset;
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
          DuelAssetIcon(asset, color: color, size: 19),
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

class _EconomySummary extends StatelessWidget {
  const _EconomySummary({required this.balance, required this.entryFee});

  final int balance;
  final int entryFee;

  @override
  Widget build(BuildContext context) {
    final values = <({String label, int value})>[
      (label: context.tr('current_balance'), value: balance),
      (label: context.tr('entry_fee'), value: entryFee),
      (label: context.tr('winner_pot'), value: entryFee * 2),
    ];
    return Card(
      color: Colors.black.withValues(alpha: .22),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 440 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 12,
              children: [
                for (final item in values)
                  SizedBox(
                    width: compact
                        ? (constraints.maxWidth - 8) / 2
                        : constraints.maxWidth / 3 - 6,
                    child: Column(
                      children: [
                        const DuelAssetIcon(
                          DuelAsset.coin,
                          size: 18,
                          color: Color(0xFFFFC94D),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.value}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          item.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .58),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
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
