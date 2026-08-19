import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/sudoku.dart';
import '../../localization/app_strings.dart';
import '../../services/push_notification_service.dart';
import '../../services/rank_identity_service.dart';
import '../../services/social_api_client.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
import '../../widgets/player_avatar.dart';
import '../duel/pre_match_ready_screen.dart';

enum ChallengeWaitingEndReason { none, declined, expired }

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
  PublicRankSummary? _recipientRank;
  bool _checking = false;
  bool _openingRoom = false;
  int _missingPolls = 0;
  ChallengeWaitingEndReason _endReason = ChallengeWaitingEndReason.none;
  String? _error;

  int get _secondsLeft => widget.challenge.expiresAt
      .difference(DateTime.now())
      .inSeconds
      .clamp(0, 24 * 60 * 60);

  bool get _ended => _endReason != ChallengeWaitingEndReason.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _push.openedRoomId.addListener(_handlePushRoom);
    unawaited(_prepareNotifications());
    unawaited(_loadRecipientRank());
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

  Future<void> _loadRecipientRank() async {
    final publicId = widget.challenge.recipient.publicId.trim();
    if (publicId.length < 3) return;
    try {
      final summary = await RankIdentityService.instance.loadPublicRankSummary(
        publicId,
      );
      if (mounted) setState(() => _recipientRank = summary);
    } catch (_) {
      // Private/non-discoverable profiles keep rank details hidden.
    }
  }

  void _handlePushRoom() {
    final roomId = _push.openedRoomId.value;
    if (roomId == null || roomId.isEmpty) return;
    _push.openedRoomId.value = null;
    unawaited(_openRoom(roomId));
  }

  Future<void> _checkStatus() async {
    if (_checking || _openingRoom || _ended || !mounted) return;
    _checking = true;
    try {
      final active = await _social.activeMatch();
      final roomId = active?['roomId']?.toString();
      if (roomId != null && roomId.isNotEmpty) {
        await _openRoom(roomId);
        return;
      }

      final pending = await _social.loadPendingChallenges();
      final stillPending = pending.any(
        (challenge) => challenge.id == widget.challenge.id,
      );
      if (stillPending) {
        _missingPolls = 0;
        if (mounted && _error != null) setState(() => _error = null);
        return;
      }

      _missingPolls++;
      if (_missingPolls < 2) return;
      _finish(inferMissingChallengeEndReason(secondsLeft: _secondsLeft));
    } on SocialApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('try_again_when_connected'));
      }
    } finally {
      _checking = false;
    }
  }

  void _finish(ChallengeWaitingEndReason reason) {
    if (!mounted || _ended) return;
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    setState(() {
      _endReason = reason;
      _error = null;
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

  String _title(BuildContext context) {
    return switch (_endReason) {
      ChallengeWaitingEndReason.declined => context.tr('challenge_declined'),
      ChallengeWaitingEndReason.expired => context.tr('challenge_timed_out'),
      ChallengeWaitingEndReason.none => context.tr('finding_opponent_title'),
    };
  }

  String _subtitle(BuildContext context) {
    return switch (_endReason) {
      ChallengeWaitingEndReason.declined => context.tr('try_again'),
      ChallengeWaitingEndReason.expired => context.tr('try_again'),
      ChallengeWaitingEndReason.none => context.tr(
        'searching_similar_opponents',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final difficulty = SudokuDifficulty.values.firstWhere(
      (value) => value.name == widget.challenge.difficulty,
      orElse: () => SudokuDifficulty.easy,
    );
    final accent = _accent(difficulty);
    final recipient = widget.challenge.recipient;
    final rank = _recipientRank?.publicId == recipient.publicId
        ? _recipientRank
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  InPageHeader(title: context.tr('challenge')),
                  Card(
                    color: const Color(0xFF101B20).withValues(alpha: .96),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                      side: BorderSide(color: accent.withValues(alpha: .48)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Column(
                        children: [
                          _StatusOrb(accent: accent, endReason: _endReason),
                          const SizedBox(height: 18),
                          Text(
                            _title(context),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _subtitle(context),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .68),
                            ),
                          ),
                          const SizedBox(height: 22),
                          PlayerAvatar(
                            displayName: recipient.displayName,
                            avatarKey:
                                rank?.avatarKey ?? 'challenge-wait-${recipient.publicId}',
                            radius: 45,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            recipient.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '@${recipient.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .54),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoChip(
                                asset: DuelAsset.grid,
                                label: context.strings.difficultyLabel(
                                  difficulty,
                                ),
                                accent: accent,
                              ),
                              _InfoChip(
                                asset: DuelAsset.trophy,
                                label: rank == null
                                    ? context.tr('games_count', <Object>[
                                        recipient.gamesPlayed,
                                      ])
                                    : '${rank.rankName} · ${rank.rankPoints} RP',
                                accent: const Color(0xFFFFC94D),
                              ),
                              if (!_ended)
                                _InfoChip(
                                  asset: DuelAsset.timer,
                                  label: '${_secondsLeft}s',
                                  accent: const Color(0xFF3AA9FF),
                                ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (_ended)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const DuelAssetIcon(
                                  DuelAsset.home,
                                  size: 21,
                                ),
                                label: Text(context.tr('main_menu')),
                              ),
                            )
                          else ...[
                            const LinearProgressIndicator(minHeight: 6),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const DuelAssetIcon(
                                DuelAsset.home,
                                size: 20,
                              ),
                              label: Text(context.tr('main_menu')),
                            ),
                          ],
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
    );
  }
}

class _StatusOrb extends StatelessWidget {
  const _StatusOrb({required this.accent, required this.endReason});

  final Color accent;
  final ChallengeWaitingEndReason endReason;

  @override
  Widget build(BuildContext context) {
    final ended = endReason != ChallengeWaitingEndReason.none;
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: .12),
        border: Border.all(color: accent.withValues(alpha: .5), width: 2),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .2), blurRadius: 28),
        ],
      ),
      alignment: Alignment.center,
      child: ended
          ? DuelAssetIcon(
              endReason == ChallengeWaitingEndReason.declined
                  ? DuelAsset.close
                  : DuelAsset.timer,
              size: 48,
            )
          : SizedBox.square(
              dimension: 48,
              child: CircularProgressIndicator(strokeWidth: 4, color: accent),
            ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.asset,
    required this.label,
    required this.accent,
  });

  final String asset;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 46, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuelAssetIcon(asset, size: 18, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
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
