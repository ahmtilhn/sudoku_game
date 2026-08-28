import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/user_safe_error.dart';

import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../duel/pre_match_ready_screen.dart';

class RematchInvitationScreen extends StatefulWidget {
  const RematchInvitationScreen({super.key, required this.invitationId});

  final String invitationId;

  @override
  State<RematchInvitationScreen> createState() =>
      _RematchInvitationScreenState();
}

class _RematchInvitationScreenState extends State<RematchInvitationScreen> {
  final EconomyService _economy = EconomyService.instance;

  RematchInvitation? _invitation;
  Timer? _timer;
  bool _loading = true;
  bool _busy = false;
  bool _openingRoom = false;
  String? _error;

  int get _secondsLeft {
    final invitation = _invitation;
    if (invitation == null) return 0;
    return invitation.expiresAt
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 10);
  }

  bool get _canRespond {
    final invitation = _invitation;
    return invitation != null &&
        !invitation.isSender &&
        invitation.status == 'pending' &&
        _secondsLeft > 0 &&
        !_busy &&
        !_openingRoom;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startClock() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        if (_invitation?.status == 'pending') {
          setState(() => _error = context.tr('challenge_timed_out'));
        }
        return;
      }
      setState(() {});
    });
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _economy.refresh(showLoading: false);
      final invitations = await _economy.loadRematches();
      RematchInvitation? invitation;
      for (final item in invitations) {
        if (item.id == widget.invitationId) {
          invitation = item;
          break;
        }
      }
      if (!mounted) return;
      if (invitation == null) {
        setState(() => _error = context.tr('challenge_timed_out'));
        return;
      }
      setState(() => _invitation = invitation);

      if (invitation.status == 'accepted' &&
          invitation.roomId?.isNotEmpty == true) {
        await _openRoom(invitation.roomId!);
        return;
      }
      if (invitation.status != 'pending' || _secondsLeft <= 0) {
        setState(() => _error = context.tr('challenge_timed_out'));
        return;
      }
      if (invitation.isSender) {
        setState(() => _error = context.tr('try_again'));
        return;
      }
      _startClock();
    } on EconomyApiException catch (error) {
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

  Future<void> _respond(bool accept) async {
    final invitation = _invitation;
    if (invitation == null || !_canRespond) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await _economy.respondRematch(
        invitationId: invitation.id,
        accept: accept,
      );
      if (!mounted) return;
      setState(() => _invitation = updated);
      if (!accept) {
        Navigator.of(context).pop();
        return;
      }
      if (updated.roomId?.isNotEmpty == true) {
        await _openRoom(updated.roomId!);
        return;
      }

      for (var attempt = 0; attempt < 12; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final values = await _economy.loadRematches();
        if (!mounted || _openingRoom) return;
        RematchInvitation? current;
        for (final item in values) {
          if (item.id == invitation.id) {
            current = item;
            break;
          }
        }
        if (current == null) continue;
        setState(() => _invitation = current);
        if (current.status == 'accepted' &&
            current.roomId?.isNotEmpty == true) {
          await _openRoom(current.roomId!);
          return;
        }
        if (current.status == 'declined' ||
            current.status == 'expired' ||
            current.status == 'insufficient_coins') {
          break;
        }
      }
      if (mounted) {
        setState(() => _error = context.tr('rematch_could_not_start'));
      }
    } on EconomyApiException catch (error) {
      if (mounted) {
        setState(() => _error = UserSafeError.message(context, error));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('rematch_could_not_start'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRoom(String roomId) async {
    if (_openingRoom || !mounted) return;
    _openingRoom = true;
    _timer?.cancel();
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => PreMatchReadyScreen(roomId: roomId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invitation = _invitation;
    final fee = invitation == null
        ? 0
        : _economy.entryFeeForDifficulty(invitation.difficulty);
    final progress = (_secondsLeft / 10).clamp(0.0, 1.0).toDouble();
    final senderName = invitation?.sender.displayName ?? 'Opponent';

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        dim: .52,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _loading
                    ? const CircularProgressIndicator()
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF17283A), Color(0xFF0B1722)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(
                              0xFF66C7FF,
                            ).withValues(alpha: .24),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .48),
                              blurRadius: 34,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF24435E),
                                    Color(0xFF102136),
                                  ],
                                ),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFC94D,
                                  ).withValues(alpha: .68),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFFC94D,
                                    ).withValues(alpha: .18),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: Text(
                                senderName.isEmpty
                                    ? '?'
                                    : senderName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'wants a rematch',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .66),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox.square(
                              dimension: 106,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 6,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: .10,
                                    ),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Color(0xFF29D398),
                                        ),
                                  ),
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '$_secondsLeft',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 38,
                                            height: 1,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        Text(
                                          's',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: .52,
                                            ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 17),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFC94D,
                                ).withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFC94D,
                                  ).withValues(alpha: .18),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const DuelAssetIcon(
                                    DuelAsset.coin,
                                    size: 18,
                                    color: Color(0xFFFFD66B),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      '$fee Coin from each player',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFFFD66B),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFF8C88),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _canRespond
                                        ? () => _respond(false)
                                        : null,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 48),
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: .18,
                                        ),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(context.tr('decline')),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _canRespond
                                        ? () => _respond(true)
                                        : null,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 48),
                                      backgroundColor: const Color(0xFF29D398),
                                      foregroundColor: const Color(0xFF071612),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: _busy
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            context.tr('accept'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
