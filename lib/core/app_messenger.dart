import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../services/online_duel_transport.dart';

class AppMessenger {
  const AppMessenger._();

  static final GlobalKey<ScaffoldMessengerState> key =
      GlobalKey<ScaffoldMessengerState>();

  static OnlineDuelConnectionState? _lastConnectionState;
  static OverlayEntry? _reconnectOverlay;

  static void showOnlineConnectionState(OnlineDuelConnectionState state) {
    if (!_bindingReady || _lastConnectionState == state) return;
    _lastConnectionState = state;
    final messenger = key.currentState;
    final context = key.currentContext;
    if (messenger == null || context == null) return;

    if (state == OnlineDuelConnectionState.connected) {
      _removeReconnectOverlay();
      messenger.clearMaterialBanners();
      return;
    }

    if (state == OnlineDuelConnectionState.reconnecting ||
        state == OnlineDuelConnectionState.resyncing) {
      messenger.clearMaterialBanners();
      _showReconnectOverlay(context);
      return;
    }

    _removeReconnectOverlay();
    final failed =
        state == OnlineDuelConnectionState.failed ||
        state == OnlineDuelConnectionState.closed;
    final text = switch (state) {
      OnlineDuelConnectionState.connecting => context.tr('connecting_players'),
      OnlineDuelConnectionState.reconnecting => context.tr('reconnecting'),
      OnlineDuelConnectionState.resyncing => context.tr(
        'connection_interrupted_retrying',
      ),
      OnlineDuelConnectionState.failed || OnlineDuelConnectionState.closed =>
        context.tr('online_account_unavailable'),
      OnlineDuelConnectionState.connected => context.tr('connected'),
    };

    messenger
      ..clearMaterialBanners()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: const Color(0xFF101C27),
          leading: Icon(
            failed ? Icons.cloud_off_outlined : Icons.sync_rounded,
            color: failed ? const Color(0xFFFF8C88) : const Color(0xFF66C7FF),
          ),
          content: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            TextButton(
              onPressed: messenger.clearMaterialBanners,
              child: Text(context.tr('dismiss')),
            ),
          ],
        ),
      );
  }

  static void _showReconnectOverlay(BuildContext context) {
    if (_reconnectOverlay != null) return;
    final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (overlayContext) => const _OnlineReconnectPresentation(),
    );
    _reconnectOverlay = entry;
    overlay.insert(entry);
  }

  static void _removeReconnectOverlay() {
    final overlay = _reconnectOverlay;
    _reconnectOverlay = null;
    overlay?.remove();
    overlay?.dispose();
  }

  static void resetOnlineConnectionState() {
    _lastConnectionState = null;
    _removeReconnectOverlay();
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

class _OnlineReconnectPresentation extends StatefulWidget {
  const _OnlineReconnectPresentation();

  @override
  State<_OnlineReconnectPresentation> createState() =>
      _OnlineReconnectPresentationState();
}

class _OnlineReconnectPresentationState
    extends State<_OnlineReconnectPresentation> {
  static const int _visualCountdownSeconds = 15;

  Timer? _timer;
  int _seconds = _visualCountdownSeconds;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_seconds <= 0) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      setState(() => _seconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expiredVisualCountdown = _seconds <= 0;
    final progress = (_seconds / _visualCountdownSeconds).clamp(0.0, 1.0);
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: .58),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Container(
                margin: const EdgeInsets.all(22),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF17283B), Color(0xFF0B1722)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFFFF6C61).withValues(alpha: .46),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .42),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: const Color(
                        0xFFFF6C61,
                      ).withValues(alpha: .10),
                      blurRadius: 26,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF6C61).withValues(alpha: .10),
                        border: Border.all(
                          color: const Color(
                            0xFFFF6C61,
                          ).withValues(alpha: .32),
                        ),
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: Color(0xFFFF7A70),
                        size: 27,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'CONNECTION LOST',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .55,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox.square(
                      dimension: 112,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: expiredVisualCountdown ? null : progress,
                            strokeWidth: 7,
                            backgroundColor: Colors.white.withValues(alpha: .10),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFFF6C61),
                            ),
                          ),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  expiredVisualCountdown ? '…' : '$_seconds',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 36,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (!expiredVisualCountdown)
                                  Text(
                                    's',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .55),
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
                    const SizedBox(height: 18),
                    Text(
                      expiredVisualCountdown
                          ? 'Still reconnecting…'
                          : 'Reconnecting…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Keep the game open while we restore the duel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .58),
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox.square(
                          dimension: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF29D398),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Match state is protected',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .48),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
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
    );
  }
}
