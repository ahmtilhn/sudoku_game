import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';
import '../../domain/sudoku.dart';
import '../../domain/sudoku_variant.dart';
import '../../localization/app_strings.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/game_modal.dart';
import '../../widgets/player_avatar.dart';
import '../duel/pre_match_ready_screen.dart';

enum ChallengeWaitingEndReason { none, declined, expired, cancelled }

ChallengeWaitingEndReason? challengeWaitingEndReasonForStatus(String status) {
  return switch (status) {
    'declined' => ChallengeWaitingEndReason.declined,
    'expired' => ChallengeWaitingEndReason.expired,
    'cancelled' => ChallengeWaitingEndReason.cancelled,
    _ => null,
  };
}

ChallengeWaitingEndReason inferMissingChallengeEndReason({
  required int secondsLeft,
}) {
  return secondsLeft > 0
      ? ChallengeWaitingEndReason.declined
      : ChallengeWaitingEndReason.expired;
}

class ChallengeWaitingScreen extends StatefulWidget {
  const ChallengeWaitingScreen({super.key, required this.challenge});

  final SocialChallenge challenge;

  @override
  State<ChallengeWaitingScreen> createState() => _ChallengeWaitingScreenState();
}

class _ChallengeWaitingScreenState extends State<ChallengeWaitingScreen>
    with WidgetsBindingObserver {
  final SocialApiClient _social = SocialApiClient.instance;
  final PushNotificationService _push = PushNotificationService.instance;

  Timer? _pollTimer;
  Timer? _clockTimer;
  late SocialChallenge _challenge;
  bool _checking = false;
  bool _openingRoom = false;
  bool _cancelling = false;
  bool _showingError = false;
  int _legacyMissingPolls = 0;
  ChallengeWaitingEndReason _endReason = ChallengeWaitingEndReason.none;
  String? _connectionNote;

  int get _secondsLeft => _challenge.expiresAt
      .difference(DateTime.now())
      .inSeconds
      .clamp(0, 24 * 60 * 60);

  bool get _ended => _endReason != ChallengeWaitingEndReason.none;

  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
    WidgetsBinding.instance.addObserver(this);
    _push.openedRoomId.addListener(_handlePushRoom);
    unawaited(_prepareNotifications());
    unawaited(_checkStatus());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_checkStatus()),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _ended) return;
      if (_secondsLeft <= 0 && !_openingRoom) {
        _finish(ChallengeWaitingEndReason.expired);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_ended) {
      unawaited(_push.refreshRegistration());
      unawaited(_checkStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _push.openedRoomId.removeListener(_handlePushRoom);
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepareNotifications() async {
    await _push.initialize();
    if (!_push.userDisabled.value) {
      await _push.refreshRegistration();
    }
  }

  void _handlePushRoom() {
    final roomId = _push.openedRoomId.value?.trim();
    if (roomId == null || roomId.isEmpty) return;
    _push.openedRoomId.value = null;
    unawaited(_openRoom(roomId));
  }

  Future<void> _checkStatus() async {
    if (_checking || _openingRoom || _ended || !mounted) return;
    _checking = true;
    try {
      final challenge = await _social.loadChallenge(_challenge.id);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _connectionNote = null;
      });
      _legacyMissingPolls = 0;

      if (challenge.status == 'pending') return;
      if (challenge.status == 'accepted') {
        final roomId = await _resolveAcceptedRoom(challenge);
        if (!mounted) return;
        if (roomId != null && roomId.isNotEmpty) {
          await _openRoom(roomId);
        } else {
          await _presentError(context.tr('matchmaking_start_failed'));
        }
        return;
      }
      final reason = challengeWaitingEndReasonForStatus(challenge.status);
      if (reason != null) {
        _finish(reason);
        return;
      }
      if (challenge.status == 'completed') {
        _finish(ChallengeWaitingEndReason.cancelled);
      }
    } on SocialApiException catch (error) {
      if (error.statusCode == 404) {
        await _checkLegacyStatusFallback();
      } else if (mounted) {
        setState(() {
          _connectionNote = context.tr('connection_interrupted_retrying');
        });
        await _presentError(UserSafeError.message(context, error));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectionNote = context.tr('connection_interrupted_retrying');
        });
        await _presentError(context.tr('try_again_when_connected'));
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _presentError(String message) async {
    if (_showingError || !mounted) return;
    _showingError = true;
    final retry = await GameModal.error(
      context,
      title: context.tr('challenge'),
      message: message,
      retryLabel: context.tr('retry'),
      cancelLabel: context.tr('cancel'),
    );
    _showingError = false;
    if (retry == true && mounted) unawaited(_checkStatus());
  }

  Future<String?> _resolveAcceptedRoom(SocialChallenge challenge) async {
    final directRoomId = challenge.roomId?.trim();
    if (directRoomId != null && directRoomId.isNotEmpty) {
      return directRoomId;
    }
    final active = await _social.activeMatch();
    final activeChallengeId = active?['challengeId']?.toString();
    final activeRoomId = active?['roomId']?.toString().trim();
    if (activeChallengeId == challenge.id &&
        activeRoomId != null &&
        activeRoomId.isNotEmpty) {
      return activeRoomId;
    }
    return null;
  }

  Future<void> _checkLegacyStatusFallback() async {
    final active = await _social.activeMatch();
    final activeChallengeId = active?['challengeId']?.toString();
    final roomId = active?['roomId']?.toString().trim();
    if (activeChallengeId == _challenge.id &&
        roomId != null &&
        roomId.isNotEmpty) {
      await _openRoom(roomId);
      return;
    }
    final pending = await _social.loadPendingChallenges();
    if (pending.any((challenge) => challenge.id == _challenge.id)) {
      _legacyMissingPolls = 0;
      return;
    }
    _legacyMissingPolls++;
    if (_legacyMissingPolls >= 2) {
      _finish(inferMissingChallengeEndReason(secondsLeft: _secondsLeft));
    }
  }

  Future<void> _cancelChallenge({bool popAfter = false}) async {
    if (_cancelling || _checking || _openingRoom || _ended || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final challenge = await _social.cancelChallenge(_challenge.id);
      if (!mounted) return;
      _challenge = challenge;
      _finish(ChallengeWaitingEndReason.cancelled);
      if (popAfter && mounted) Navigator.of(context).pop();
    } on SocialApiException catch (error) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      if (error.statusCode == 409) {
        await _checkStatus();
      } else {
        await _presentError(UserSafeError.message(context, error));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cancelling = false);
        await _presentError(context.tr('try_again_when_connected'));
      }
    }
  }

  void _finish(ChallengeWaitingEndReason reason) {
    if (!mounted || _ended) return;
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    setState(() {
      _endReason = reason;
      _cancelling = false;
      _connectionNote = null;
    });
  }

  Future<void> _openRoom(String roomId) async {
    if (_openingRoom || !mounted) return;
    _openingRoom = true;
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),
    );
  }

  String _title(BuildContext context) => switch (_endReason) {
    ChallengeWaitingEndReason.declined => context.tr('challenge_declined'),
    ChallengeWaitingEndReason.expired => context.tr('challenge_timed_out'),
    ChallengeWaitingEndReason.cancelled => context.tr('cancel_search'),
    ChallengeWaitingEndReason.none => context.tr('finding_opponent_title'),
  };

  String _subtitle(BuildContext context) => switch (_endReason) {
    ChallengeWaitingEndReason.declined ||
    ChallengeWaitingEndReason.expired ||
    ChallengeWaitingEndReason.cancelled => context.tr('try_again'),
    ChallengeWaitingEndReason.none =>
      _connectionNote ?? context.tr('searching_similar_opponents'),
  };

  @override
  Widget build(BuildContext context) {
    final difficulty = SudokuDifficulty.values.firstWhere(
      (value) => value.name == _challenge.difficulty,
      orElse: () => SudokuDifficulty.easy,
    );
    final recipient = _challenge.recipient;
    final is16 = _challenge.variant.id == SudokuVariantId.classic16;
    final accent = is16 ? const Color(0xFF35D2FF) : const Color(0xFFFFC73D);

    return PopScope(
      canPop: _ended || _openingRoom,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancelChallenge(popAfter: true));
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07111E),
        body: AppBackdrop(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 700;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Padding(
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
                                onPressed: _ended
                                    ? () => Navigator.of(context).pop()
                                    : () => _cancelChallenge(popAfter: true),
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
                            ],
                          ),
                          const Spacer(),
                          DuelAssetIcon(
                            is16 ? DuelAsset.board16Pro : DuelAsset.board9Pro,
                            size: compact ? 126 : 162,
                          ),
                          SizedBox(height: compact ? 8 : 14),
                          Text(
                            _title(context),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 23 : 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _subtitle(context),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .66),
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 16),
                          PlayerAvatar(
                            displayName: recipient.displayName,
                            avatarKey: 'challenge-wait-${recipient.publicId}',
                            radius: compact ? 35 : 44,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            recipient.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '@${recipient.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .52),
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 15),
                          Row(
                            children: [
                              Expanded(
                                child: _InfoPill(
                                  icon: Icons.grid_4x4_rounded,
                                  label: _challenge.variant.label,
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
                                  icon: Icons.timer_outlined,
                                  label: _ended ? '—' : '${_secondsLeft}s',
                                  accent: const Color(0xFF7A5CFF),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (!_ended)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _cancelling
                                    ? null
                                    : () => _cancelChallenge(popAfter: true),
                                icon: _cancelling
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.close_rounded),
                                label: Text(context.tr('cancel_search')),
                              ),
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: Text(context.tr('main_menu')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
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
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1728).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent, size: 18),
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
