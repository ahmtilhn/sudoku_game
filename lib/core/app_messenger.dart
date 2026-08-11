import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../services/online_duel_transport.dart';

class AppMessenger {
  const AppMessenger._();

  static final GlobalKey<ScaffoldMessengerState> key =
      GlobalKey<ScaffoldMessengerState>();

  static OnlineDuelConnectionState? _lastConnectionState;

  static void showOnlineConnectionState(OnlineDuelConnectionState state) {
    if (!_bindingReady || _lastConnectionState == state) return;
    _lastConnectionState = state;
    final messenger = key.currentState;
    final context = key.currentContext;
    if (messenger == null || context == null) return;

    if (state == OnlineDuelConnectionState.connected) {
      messenger.clearMaterialBanners();
      return;
    }

    final failed = state == OnlineDuelConnectionState.failed ||
        state == OnlineDuelConnectionState.closed;
    final text = switch (state) {
      OnlineDuelConnectionState.connecting =>
        context.tr('connecting_players'),
      OnlineDuelConnectionState.reconnecting => context.tr('reconnecting'),
      OnlineDuelConnectionState.resyncing =>
        context.tr('connection_interrupted_retrying'),
      OnlineDuelConnectionState.failed || OnlineDuelConnectionState.closed =>
        context.tr('online_account_unavailable'),
      OnlineDuelConnectionState.connected => context.tr('connected'),
    };

    messenger
      ..clearMaterialBanners()
      ..showMaterialBanner(
        MaterialBanner(
          leading: Icon(
            failed ? Icons.cloud_off_outlined : Icons.sync_rounded,
          ),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: messenger.clearMaterialBanners,
              child: Text(context.tr('dismiss')),
            ),
          ],
        ),
      );
  }

  static void resetOnlineConnectionState() {
    _lastConnectionState = null;
    if (!_bindingReady) return;
    key.currentState?.clearMaterialBanners();
  }

  static bool get _bindingReady {
    try {
      WidgetsBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }
}
