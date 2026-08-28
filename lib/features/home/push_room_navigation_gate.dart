import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/firebase_session_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/social_api_client.dart';
import '../duel/pre_match_ready_screen.dart';
import '../social/rematch_invitation_screen.dart';
import '../social/social_hub_screen.dart';

class PushRoomNavigationGate extends StatefulWidget {
  const PushRoomNavigationGate({super.key, required this.child});

  final Widget child;

  @override
  State<PushRoomNavigationGate> createState() => _PushRoomNavigationGateState();
}

class _PushRoomNavigationGateState extends State<PushRoomNavigationGate>
    with WidgetsBindingObserver {
  final PushNotificationService _push = PushNotificationService.instance;
  Timer? _retryTimer;
  bool _routing = false;
  int _retryAttempt = 0;

  bool get _hasHandledPendingNavigation =>
      _push.openedRoomId.value?.isNotEmpty == true ||
      _push.openedRematchId.value?.isNotEmpty == true ||
      _push.openedSocialId.value?.isNotEmpty == true;

  bool get _routeAllowsAutomaticNavigation =>
      ModalRoute.of(context)?.isCurrent ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _push.openedRoomId.addListener(_scheduleRouting);
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
    _push.openedRematchId.removeListener(_scheduleRouting);
    _push.openedSocialId.removeListener(_scheduleRouting);
    super.dispose();
  }

  Future<void> _initializePush() async {
    try {
      // Restore the Play Games/Firebase player before obtaining and registering
      // the FCM token. Otherwise a cold start could attach the device token to
      // a temporary guest UID and direct challenges would notify the wrong
      // account (or no visible device at all).
      await FirebaseSessionService.ensureAnonymousSession();
      await _push.initialize();
      await _refreshPushRegistration();
    } catch (_) {
      // Offline play must stay available. Registration is retried on resume.
    }
    if (mounted) _scheduleRouting();
  }

  Future<void> _refreshPushRegistration() async {
    if (!_push.configured || _push.userDisabled.value) return;
    try {
      await FirebaseSessionService.ensureAnonymousSession();
      await _push.refreshRegistration();
    } catch (_) {
      // Best effort; foreground routing/polling remains available.
    }
  }

  void _scheduleRouting() {
    _retryTimer?.cancel();
    _retryTimer = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_routePendingDestination());
    });
  }

  void _scheduleRetry() {
    if (!mounted || _retryTimer != null || !_hasHandledPendingNavigation) {
      return;
    }
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
    if (!mounted ||
        _routing ||
        !_hasHandledPendingNavigation ||
        !_routeAllowsAutomaticNavigation) {
      return;
    }

    final roomId = _push.openedRoomId.value?.trim();
    final rematchId = _push.openedRematchId.value?.trim();
    final socialId = _push.openedSocialId.value?.trim();
    if ((roomId == null || roomId.isEmpty) &&
        (rematchId == null || rematchId.isEmpty) &&
        (socialId == null || socialId.isEmpty)) {
      return;
    }

    _routing = true;
    if (roomId != null && roomId.isNotEmpty) {
      _push.openedRoomId.value = null;
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
      } else if (rematchId != null && rematchId.isNotEmpty) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RematchInvitationScreen(invitationId: rematchId),
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
      } else if (rematchId != null && rematchId.isNotEmpty) {
        _push.openedRematchId.value ??= rematchId;
      } else if (socialId != null && socialId.isNotEmpty) {
        _push.openedSocialId.value ??= socialId;
      }
      _scheduleRetry();
    } finally {
      _routing = false;
      if (_hasHandledPendingNavigation && _routeAllowsAutomaticNavigation) {
        _scheduleRouting();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (routeIsCurrent && _hasHandledPendingNavigation && !_routing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleRouting();
      });
    }
    return widget.child;
  }
}
