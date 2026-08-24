import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/firebase_session_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../duel/pre_match_ready_screen.dart';
import '../social/rematch_invitation_screen.dart';
import '../social/ux_challenge_invitation_screen.dart';

class PushRoomNavigationGate extends StatefulWidget {
  const PushRoomNavigationGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<PushRoomNavigationGate> createState() =>
      _PushRoomNavigationGateState();
}

class _PushRoomNavigationGateState extends State<PushRoomNavigationGate> {
  final PushNotificationService _push = PushNotificationService.instance;
  Timer? _retryTimer;
  bool _routing = false;
  int _retryAttempt = 0;

  @override
  void initState() {
    super.initState();
    _push.openedRoomId.addListener(_scheduleRouting);
    _push.openedChallengeId.addListener(_scheduleRouting);
    _push.openedRematchId.addListener(_scheduleRouting);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRouting());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _push.openedRoomId.removeListener(_scheduleRouting);
    _push.openedChallengeId.removeListener(_scheduleRouting);
    _push.openedRematchId.removeListener(_scheduleRouting);
    super.dispose();
  }

  void _scheduleRouting() {
    _retryTimer?.cancel();
    _retryTimer = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_routePendingDestination());
    });
  }

  void _scheduleRetry() {
    if (!mounted || _retryTimer != null || !_push.hasPendingNavigation) return;
    _retryAttempt++;
    final delay = switch (_retryAttempt) {
      <= 2 => const Duration(milliseconds: 350),
      <= 5 => const Duration(milliseconds: 750),
      _ => const Duration(seconds: 2),
    };
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _scheduleRouting();
    });
  }

  Future<void> _routePendingDestination() async {
    if (!mounted || _routing || !_push.hasPendingNavigation) return;

    final roomId = _push.openedRoomId.value?.trim();
    final challengeId = _push.openedChallengeId.value?.trim();
    final rematchId = _push.openedRematchId.value?.trim();
    if ((roomId == null || roomId.isEmpty) &&
        (challengeId == null || challengeId.isEmpty) &&
        (rematchId == null || rematchId.isEmpty)) {
      return;
    }

    _routing = true;
    if (roomId != null && roomId.isNotEmpty) {
      _push.openedRoomId.value = null;
    } else if (challengeId != null && challengeId.isNotEmpty) {
      _push.openedChallengeId.value = null;
    } else if (rematchId != null && rematchId.isNotEmpty) {
      _push.openedRematchId.value = null;
    }

    try {
      await FirebaseSessionService.ensureAnonymousSession();
      if (SocialApiClient.instance.configured) {
        await SocialApiClient.instance.ensureProfile();
      }
      if (!mounted) return;

      _retryAttempt = 0;
      if (roomId != null && roomId.isNotEmpty) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => PreMatchReadyScreen(roomId: roomId),
          ),
        );
      } else if (challengeId != null && challengeId.isNotEmpty) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => UxChallengeInvitationScreen(
              challengeId: challengeId,
            ),
          ),
        );
      } else if (rematchId != null && rematchId.isNotEmpty) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RematchInvitationScreen(
              invitationId: rematchId,
            ),
          ),
        );
      }
    } catch (_) {
      if (roomId != null && roomId.isNotEmpty) {
        _push.openedRoomId.value ??= roomId;
      } else if (challengeId != null && challengeId.isNotEmpty) {
        _push.openedChallengeId.value ??= challengeId;
      } else if (rematchId != null && rematchId.isNotEmpty) {
        _push.openedRematchId.value ??= rematchId;
      }
      _scheduleRetry();
    } finally {
      _routing = false;
      if (_push.hasPendingNavigation) _scheduleRouting();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
