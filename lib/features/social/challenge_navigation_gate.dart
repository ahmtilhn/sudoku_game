import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_progress_store.dart';
import '../../services/push_notification_service.dart';
import 'challenge_invitation_screen.dart';
import 'player_identity_gate.dart';

class ChallengeNavigationGate extends StatefulWidget {
  const ChallengeNavigationGate({super.key, required this.store});

  final LocalProgressStore store;

  @override
  State<ChallengeNavigationGate> createState() =>
      _ChallengeNavigationGateState();
}

class _ChallengeNavigationGateState extends State<ChallengeNavigationGate> {
  final PushNotificationService _push = PushNotificationService.instance;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _push.openedChallengeId.addListener(_scheduleOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleOpen());
  }

  @override
  void dispose() {
    _push.openedChallengeId.removeListener(_scheduleOpen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlayerIdentityGate(store: widget.store);

  void _scheduleOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openChallenge());
    });
  }

  Future<void> _openChallenge() async {
    if (!mounted || _opening || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    final challengeId = _push.openedChallengeId.value;
    if (challengeId == null || challengeId.isEmpty) return;

    _opening = true;
    _push.openedChallengeId.value = null;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChallengeInvitationScreen(challengeId: challengeId),
        ),
      );
    } finally {
      _opening = false;
      if (mounted && _push.openedChallengeId.value != null) _scheduleOpen();
    }
  }
}
