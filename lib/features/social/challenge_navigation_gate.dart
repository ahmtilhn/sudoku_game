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
  bool _openingChallenge = false;

  @override
  void initState() {
    super.initState();
    _push.openedChallengeId.addListener(_onOpenedChallenge);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleOpenedChallenge());
    });
  }

  @override
  void dispose() {
    _push.openedChallengeId.removeListener(_onOpenedChallenge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerIdentityGate(store: widget.store);
  }

  void _onOpenedChallenge() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleOpenedChallenge());
    });
  }

  Future<void> _handleOpenedChallenge() async {
    if (!mounted || _openingChallenge) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;

    final challengeId = _push.openedChallengeId.value;
    if (challengeId == null || challengeId.isEmpty) return;

    _openingChallenge = true;
    _push.openedChallengeId.value = null;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChallengeInvitationScreen(
            challengeId: challengeId,
          ),
        ),
      );
    } finally {
      _openingChallenge = false;
      if (mounted && _push.openedChallengeId.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_handleOpenedChallenge());
        });
      }
    }
  }
}
