import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/push_notification_service.dart';
import '../duel/pre_match_ready_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _push.openedRoomId.addListener(_scheduleRouting);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRouting());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _push.openedRoomId.removeListener(_scheduleRouting);
    super.dispose();
  }

  void _scheduleRouting() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_routePendingRoom());
    });
  }

  Future<void> _routePendingRoom() async {
    if (!mounted || _routing) return;
    final roomId = _push.openedRoomId.value?.trim();
    if (roomId == null || roomId.isEmpty) return;

    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (!routeIsCurrent) {
      _retryTimer = Timer(const Duration(milliseconds: 500), _scheduleRouting);
      return;
    }

    _routing = true;
    _push.openedRoomId.value = null;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PreMatchReadyScreen(roomId: roomId),
        ),
      );
    } finally {
      _routing = false;
      if (_push.openedRoomId.value?.isNotEmpty == true) {
        _scheduleRouting();
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
