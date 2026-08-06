import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../domain/sudoku_variant.dart';
import '../../localization/app_strings.dart';
import '../../services/economy_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
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
  bool _showingError = false;
  String? _statusMessage;

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

  bool get _hasBalance => _economy.balance >= _entryFee;
  bool get _canAccept => !_expired && _hasBalance;

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

  Future<void> _load() async {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _statusMessage = null;
      });
    }
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
        setState(() => _statusMessage = _messageForStatus(challenge.status));
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _statusTicks++;
        if (_secondsLeft <= 0) _timer?.cancel();
        setState(() {});
        if (_statusTicks.isEven) unawaited(_refreshStatus());
      });
    } catch (error) {
      if (mounted) {
        await _presentError(
          error,
          retry: _load,
        );
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
          _statusMessage = _messageForStatus(challenge.status);
        }
      });
      if (challenge.status == 'accepted') {
        final roomId = await _resolveRoomId(challenge);
        if (roomId != null && roomId.isNotEmpty) await _openRoom(roomId);
      }
    } catch (_) {
      // Explicit actions surface failures; polling remains quiet.
    }
  }

  String _messageForStatus(String status) => switch (status) {
    'declined' => context.tr('challenge_declined'),
    'expired' => context.tr('challenge_timed_out'),
    'cancelled' => context.tr('cancel_search'),
    _ => context.tr('challenge_timed_out'),
  };

  Future<void> _respond(bool accept) async {
    final challenge = _challenge;
    if (challenge == null || _busy || _expired) return;
    if (accept && !_canAccept) {
      final openStore = await GameModal.warning(
        context,
        title: context.tr('coin_required_title_dynamic', <Object>[_entryFee]),
        message: context.tr('not_enough_coins_online', <Object>[_entryFee]),
        confirmLabel: context.tr('open_coin_store'),
        cancelLabel: context.tr('cancel'),
      );
      if (openStore && mounted) await _openStore();
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await _social.respondToChallenge(
        challengeId: challenge.id,
        accept: accept,
      );
      if (!mounted) return;
      if (!accept) {
        await GameModal.success(
          context,
          title: context.tr('challenge'),
          message: context.tr('challenge_declined'),
          actionLabel: context.tr('continue_action'),
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final roomId = await _resolveRoomId(result);
      if (!mounted) return;
      if (roomId == null || roomId.isEmpty) {
        await _presentError(
          const SocialApiException(0, 'Match room was not ready.'),
          retry: () => _respond(true),
        );
        return;
      }
      await _openRoom(roomId);
    } catch (error) {
      if (accept && await _recoverAcceptedChallenge()) return;
      if (mounted) {
        await _presentError(error, retry: () => _respond(accept));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _presentError(
    Object error, {
    Future<void> Function()? retry,
  }) async {
    if (_showingError || !mounted) return;
    _showingError = true;
    final shouldRetry = await GameModal.error(
      context,
      title: context.tr('challenge'),
      message: UserSafeError.message(context, error),
      retryLabel: retry == null ? context.tr('continue_action') : context.tr('retry'),
      cancelLabel: context.tr('cancel'),
    );
    _showingError = false;
    if (shouldRetry == true && retry != null && mounted) {
      unawaited(retry());
    }
  }

  Future<String?> _resolveRoomId(SocialChallenge result) async {
    final directRoomId = result.roomId?.trim();
    if (directRoomId != null && directRoomId.isNotEmpty) return directRoomId;
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
        // Backend may still be repairing the accepted room.
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CoinStoreScreen()),
    );
    await _economy.refresh(showLoading: false);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _challenge == null
                  ? _unavailable()
                  : _content(_challenge!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _unavailable() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DuelAssetIcon(DuelAsset.statusWarningPro, size: 150),
          const SizedBox(height: 14),
          Text(
            _statusMessage ?? context.tr('challenge_timed_out'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('try_again')),
          ),
        ],
      ),
    );
  }

  Widget _content(SocialChallenge challenge) {
    final difficulty = SudokuDifficulty.values.firstWhere(
      (value) => value.name == challenge.difficulty,
      orElse: () => SudokuDifficulty.easy,
    );
    final is16 = challenge.variant.id == SudokuVariantId.classic16;
    final accent = is16 ? const Color(0xFF35D2FF) : const Color(0xFFFFC73D);
    final challenger = challenge.challenger;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 700;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            compact ? 8 : 14,
            16,
            compact ? 10 : 18,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('challenge'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _InfoPill(
                    icon: Icons.timer_outlined,
                    label: _expired ? '—' : '${_secondsLeft}s',
                    accent: _expired ? Colors.white38 : const Color(0xFF7A5CFF),
                  ),
                ],
              ),
              const Spacer(),
              DuelAssetIcon(
                is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                size: compact ? 128 : 166,
              ),
              SizedBox(height: compact ? 7 : 12),
              PlayerAvatar(
                displayName: challenger.displayName,
                avatarKey: 'challenge-${challenger.publicId}',
                radius: compact ? 34 : 43,
              ),
              const SizedBox(height: 7),
              Text(
                challenger.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '@${challenger.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: .52)),
              ),
              SizedBox(height: compact ? 9 : 14),
              Row(
                children: [
                  Expanded(
                    child: _InfoPill(
                      icon: Icons.grid_4x4_rounded,
                      label: challenge.variant.label,
                      accent: accent,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _InfoPill(
                      icon: Icons.tune_rounded,
                      label: context.strings.difficultyLabel(difficulty),
                      accent: const Color(0xFF29D398),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _InfoPill(
                      icon: Icons.monetization_on_rounded,
                      label: '$_entryFee',
                      accent: const Color(0xFFFFC73D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${context.tr('balance_coin', <Object>[_economy.balance])} · ${context.tr('rating_value', <Object>[challenger.rating])}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: .64)),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFFC73D)),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || _expired ? null : () => _respond(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: accent,
                    foregroundColor: const Color(0xFF07111E),
                  ),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _hasBalance
                      ? const Icon(Icons.sports_kabaddi_rounded)
                      : const Icon(Icons.storefront_rounded),
                  label: Text(
                    _hasBalance
                        ? context.tr('accept')
                        : context.tr('open_coin_store'),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _busy || _expired ? null : () => _respond(false),
                  child: Text(context.tr('decline')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent, size: 17),
          const SizedBox(width: 5),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
