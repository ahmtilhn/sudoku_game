import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/economy_api_client.dart';
import '../../services/economy_service.dart';
import '../../widgets/app_backdrop.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        InPageHeader(title: context.tr('challenge')),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                const Icon(Icons.replay_rounded, size: 56),
                                const SizedBox(height: 12),
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                if (invitation != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${invitation.sender.displayName} · ${invitation.difficulty}',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_secondsLeft}s',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
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
                                FilledButton.icon(
                                  onPressed: _canRespond
                                      ? () => _respond(true)
                                      : null,
                                  icon: const Icon(Icons.check_rounded),
                                  label: Text(context.tr('accept')),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _canRespond
                                      ? () => _respond(false)
                                      : null,
                                  child: Text(context.tr('decline')),
                                ),
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
