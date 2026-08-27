import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/in_page_header.dart';
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

      // Accept writes the room in the same authoritative backend operation, but
      // keep a short recovery poll for network retries / older Worker versions.
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
      if (mounted) setState(() => _error = error.message);
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

    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        dim: .34,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Column(
                  children: [
                    InPageHeader(title: context.tr('challenge')),
                    Expanded(
                      child: Center(
                        child: _loading
                            ? const CircularProgressIndicator()
                            : Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  24,
                                  20,
                                  20,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF17283A),
                                      Color(0xFF0B1722),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF29D398,
                                    ).withValues(alpha: .30),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: .32),
                                      blurRadius: 28,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 70,
                                      height: 70,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(
                                          0xFF29D398,
                                        ).withValues(alpha: .09),
                                        border: Border.all(
                                          color: const Color(
                                            0xFFFFC94D,
                                          ).withValues(alpha: .30),
                                        ),
                                      ),
                                      child: const Center(
                                        child: DuelAssetIcon(
                                          DuelAsset.refresh,
                                          size: 35,
                                          color: Color(0xFFFFD66B),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      context.tr('rematch_invitation_title'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 23,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      invitation == null
                                          ? context.tr('challenge_timed_out')
                                          : context.tr(
                                              'wants_to_play_again',
                                              <Object>[
                                                invitation.sender.displayName,
                                              ],
                                            ),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: .66),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (invitation != null) ...[
                                      const SizedBox(height: 18),
                                      SizedBox.square(
                                        dimension: 112,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            CircularProgressIndicator(
                                              value: progress,
                                              strokeWidth: 7,
                                              backgroundColor: Colors.white
                                                  .withValues(alpha: .10),
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                    Color
                                                  >(Color(0xFF29D398)),
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
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  Text(
                                                    's',
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: .50,
                                                          ),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFFFC94D,
                                          ).withValues(alpha: .08),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFFFFC94D,
                                            ).withValues(alpha: .20),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const DuelAssetIcon(
                                              DuelAsset.coin,
                                              size: 19,
                                              color: Color(0xFFFFD66B),
                                            ),
                                            const SizedBox(width: 7),
                                            Flexible(
                                              child: Text(
                                                context.tr(
                                                  'rematch_requires_coin',
                                                  <Object>[fee],
                                                ),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Color(0xFFFFD66B),
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${invitation.difficulty} · ${context.tr('balance_coin', <Object>[_economy.balance])}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: .46,
                                          ),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    if (_error != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFFFF8C88),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _canRespond
                                                ? () => _respond(false)
                                                : null,
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 50),
                                              foregroundColor: Colors.white,
                                              side: BorderSide(
                                                color: Colors.white.withValues(
                                                  alpha: .16,
                                                ),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            child: Text(context.tr('decline')),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: _canRespond
                                                ? () => _respond(true)
                                                : null,
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(0, 50),
                                              backgroundColor: const Color(
                                                0xFF29D398,
                                              ),
                                              foregroundColor: const Color(
                                                0xFF071612,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            child: _busy
                                                ? const SizedBox.square(
                                                    dimension: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : Text(
                                                    context.tr('accept'),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
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
