import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/firebase_session_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../duel/pre_match_ready_screen.dart';
import '../social/rematch_invitation_screen.dart';
import '../social/social_hub_screen.dart';
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

class _PushRoomNavigationGateState extends State<PushRoomNavigationGate>
    with WidgetsBindingObserver {
  final PushNotificationService _push = PushNotificationService.instance;
  Timer? _retryTimer;
  bool _routing = false;
  int _retryAttempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _push.openedRoomId.addListener(_scheduleRouting);
    _push.openedChallengeId.addListener(_scheduleRouting);
    _push.openedRematchId.addListener(_scheduleRouting);
    _push.openedSocialId.addListener(_scheduleRouting);
    unawaited(_initializePush());
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRouting());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPushRegistration());
      _scheduleRouting();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _push.openedRoomId.removeListener(_scheduleRouting);
    _push.openedChallengeId.removeListener(_scheduleRouting);
    _push.openedRematchId.removeListener(_scheduleRouting);
    _push.openedSocialId.removeListener(_scheduleRouting);
    super.dispose();
  }

  Future<void> _initializePush() async {
    await _push.initialize();
    await _refreshPushRegistration();
    if (mounted) _scheduleRouting();
  }

  Future<void> _refreshPushRegistration() async {
    if (!_push.configured || _push.userDisabled.value) return;
    await _push.refreshRegistration();
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
    final socialId = _push.openedSocialId.value?.trim();
    if ((roomId == null || roomId.isEmpty) &&
        (challengeId == null || challengeId.isEmpty) &&
        (rematchId == null || rematchId.isEmpty) &&
        (socialId == null || socialId.isEmpty)) {
      return;
    }

    _routing = true;
    if (roomId != null && roomId.isNotEmpty) {
      _push.openedRoomId.value = null;
    } else if (challengeId != null && challengeId.isNotEmpty) {
      _push.openedChallengeId.value = null;
    } else if (rematchId != null && rematchId.isNotEmpty) {
      _push.openedRematchId.value = null;
    } else if (socialId != null && socialId.isNotEmpty) {
      _push.openedSocialId.value = null;
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
      } else if (socialId != null && socialId.isNotEmpty) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const SocialHubScreen()),
        );
      }
    } catch (_) {
      if (roomId != null && roomId.isNotEmpty) {
        _push.openedRoomId.value ??= roomId;
      } else if (challengeId != null && challengeId.isNotEmpty) {
        _push.openedChallengeId.value ??= challengeId;
      } else if (rematchId != null && rematchId.isNotEmpty) {
        _push.openedRematchId.value ??= rematchId;
      } else if (socialId != null && socialId.isNotEmpty) {
        _push.openedSocialId.value ??= socialId;
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
