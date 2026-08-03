import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/player_avatar.dart';
import 'online_duel_screen.dart';

class PreMatchReadyScreen extends StatefulWidget {
  const PreMatchReadyScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<PreMatchReadyScreen> createState() => _PreMatchReadyScreenState();
}

class _PreMatchReadyScreenState extends State<PreMatchReadyScreen> {
  OnlineDuelController? _controller;
  StreamSubscription<OnlineDuelSnapshot>? _snapshotSubscription;
  StreamSubscription<OnlineDuelConnectionState>? _connectionSubscription;
  OnlineDuelSnapshot? _snapshot;
  OnlineDuelConnectionState _connectionState =
      OnlineDuelConnectionState.connecting;
  Object? _error;
  bool _readyPressed = false;
  bool _screenLoadedSent = false;
  bool _handedOff = false;
  bool _connecting = false;
  bool _leaving = false;
  Timer? _retryTimer;
  int _connectAttempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(_snapshotSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    if (!_handedOff) unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting || _handedOff || !mounted) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    setState(() {
      _connecting = true;
      _error = null;
      _connectionState = OnlineDuelConnectionState.connecting;
    });

    await _snapshotSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _controller?.dispose();
    _controller = null;

    try {
      final transport = await WebSocketOnlineDuelTransport.connect(widget.roomId);
      final controller = OnlineDuelController(transport)..start();
      final snapshotSubscription = controller.snapshots.listen((snapshot) {
        if (!mounted) return;
        setState(() {
          _snapshot = snapshot;
          _error = null;
          if (snapshot.players[snapshot.youSeat]?.ready == true) {
            _readyPressed = true;
          }
        });
        _sendScreenLoaded();
        if (snapshot.status == OnlineDuelStatus.active) {
          unawaited(_openMatch(controller));
        }
      });
      final connectionSubscription = controller.connectionStates.listen((state) {
        if (!mounted) return;
        setState(() => _connectionState = state);
      });

      if (!mounted) {
        await snapshotSubscription.cancel();
        await connectionSubscription.cancel();
        await controller.dispose();
        return;
      }
      _connectAttempt = 0;
      setState(() {
        _controller = controller;
        _snapshotSubscription = snapshotSubscription;
        _connectionSubscription = connectionSubscription;
        _connectionState = controller.connectionState;
      });
      controller.requestSnapshot();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _connectionState = OnlineDuelConnectionState.failed;
      });
      _scheduleReconnect();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _scheduleReconnect() {
    if (!mounted || _handedOff || _retryTimer != null) return;
    _connectAttempt++;
    final seconds = switch (_connectAttempt) {
      <= 1 => 1,
      2 => 2,
      3 => 4,
      _ => 6,
    };
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      if (mounted && !_handedOff) unawaited(_connect());
    });
  }

  void _sendScreenLoaded() {
    if (_screenLoadedSent || _snapshot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _screenLoadedSent) return;
      _screenLoadedSent = true;
      _controller?.screenLoaded();
    });
  }

  Future<void> _cancelAndLeave() async {
    if (_leaving || _handedOff || !mounted) return;
    setState(() => _leaving = true);
    final controller = _controller;
    if (controller == null) {
      _handedOff = true;
      if (mounted) Navigator.of(context).pop();
      return;
    }
    controller.forfeit();
    for (var attempt = 0; attempt < 24; attempt++) {
      controller.requestSnapshot();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final snapshot = _snapshot;
      if (snapshot != null &&
          snapshot.isFinished &&
          (snapshot.coinSettlement != null || attempt >= 10)) {
        break;
      }
    }
    if (!mounted) return;
    _handedOff = true;
    Navigator.of(context).pop();
  }

  void _ready() {
    if (_readyPressed || _controller == null) return;
    setState(() => _readyPressed = true);
    _controller!.ready();
  }

  Future<void> _openMatch(OnlineDuelController controller) async {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    await _snapshotSubscription?.cancel();
    await _connectionSubscription?.cancel();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<String?, void>(
      MaterialPageRoute(
        builder: (_) => OnlineDuelScreen(
          roomId: widget.roomId,
          controller: controller,
        ),
      ),
    );
  }

  OnlineDuelPlayer? get _you {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    return snapshot.players[snapshot.youSeat];
  }

  OnlineDuelPlayer? get _opponent {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    final seat = snapshot.youSeat == OnlineDuelSeat.a
        ? OnlineDuelSeat.b
        : OnlineDuelSeat.a;
    return snapshot.players[seat];
  }

  bool get _readyStage {
    final status = _snapshot?.status;
    return status == OnlineDuelStatus.waiting ||
        status == OnlineDuelStatus.readyWindow;
  }

  bool get _youReady => _readyPressed || _you?.ready == true;
  bool get _opponentReady => _opponent?.ready == true;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _handedOff,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancelAndLeave());
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: LayoutBuilder(
                  builder: (context, viewport) {
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final compact = viewport.maxHeight < 680 || textScale > 1.3;
                    return Column(
                      children: [
                        Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip: context.tr('cancel_search'),
                              onPressed: _leaving ? null : _cancelAndLeave,
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _readyStage
                                    ? context.tr('ready_question')
                                    : context.tr('finding_opponent_title'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 19 : 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 10 : 16),
                        _ConnectionBanner(
                          state: _connectionState,
                          error: _error,
                          onRetry: _connecting ? null : _connect,
                        ),
                        SizedBox(height: compact ? 10 : 18),
                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final vertical =
                                    constraints.maxWidth < 520 || textScale > 1.3;
                                final youCard = _PlayerCard(
                                  player: _you,
                                  fallbackName: context.tr('you'),
                                  ready: _youReady,
                                  accent: const Color(0xFF29D398),
                                  compact: compact,
                                );
                                final opponentCard = _PlayerCard(
                                  player: _opponent,
                                  fallbackName: context.tr('opponent'),
                                  ready: _opponentReady,
                                  accent: const Color(0xFF7A5CFF),
                                  compact: compact,
                                );
                                return Column(
                                  children: [
                                    if (vertical) ...[
                                      youCard,
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: compact ? 6 : 10,
                                        ),
                                        child: const Icon(
                                          Icons.flash_on_rounded,
                                          color: Color(0xFFFFC94D),
                                          size: 34,
                                        ),
                                      ),
                                      opponentCard,
                                    ] else
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(child: youCard),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                            child: Icon(
                                              Icons.flash_on_rounded,
                                              color: Color(0xFFFFC94D),
                                              size: 34,
                                            ),
                                          ),
                                          Expanded(child: opponentCard),
                                        ],
                                      ),
                                    SizedBox(height: compact ? 10 : 16),
                                    Text(
                                      _statusText(context),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: .74,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                _leaving ||
                                    !_readyStage ||
                                    _youReady ||
                                    _controller == null ||
                                    _connectionState ==
                                        OnlineDuelConnectionState.failed
                                ? null
                                : _ready,
                            icon: Icon(
                              _youReady
                                  ? Icons.check_circle_rounded
                                  : Icons.shield_outlined,
                            ),
                            label: Text(
                              _youReady
                                  ? context.tr('ready')
                                  : context.tr('i_am_ready'),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _statusText(BuildContext context) {
    if (!_readyStage) return context.tr('searching_similar_opponents');
    if (_youReady && _opponentReady) {
      return context.tr('everyone_ready_starting');
    }
    if (_youReady) return context.tr('you_ready_waiting_opponent');
    if (_opponentReady) return context.tr('opponent_ready_waiting_you');
    return context.tr('match_ready_prompt');
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.state,
    required this.error,
    required this.onRetry,
  });

  final OnlineDuelConnectionState state;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = state == OnlineDuelConnectionState.failed || error != null;
    final color = failed
        ? Theme.of(context).colorScheme.error
        : state == OnlineDuelConnectionState.connected
        ? const Color(0xFF29D398)
        : const Color(0xFFFFC94D);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .34)),
      ),
      child: Row(
        children: [
          Icon(_icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _label(context),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          if (failed)
            IconButton(
              tooltip: context.tr('retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }

  IconData get _icon {
    return switch (state) {
      OnlineDuelConnectionState.connected => Icons.cloud_done_outlined,
      OnlineDuelConnectionState.reconnecting ||
      OnlineDuelConnectionState.resyncing => Icons.sync_rounded,
      OnlineDuelConnectionState.failed ||
      OnlineDuelConnectionState.closed => Icons.cloud_off_outlined,
      OnlineDuelConnectionState.connecting => Icons.cloud_sync_outlined,
    };
  }

  String _label(BuildContext context) {
    return switch (state) {
      OnlineDuelConnectionState.connected => context.tr('connected'),
      OnlineDuelConnectionState.reconnecting => context.tr('reconnecting'),
      OnlineDuelConnectionState.resyncing =>
        context.tr('connection_interrupted_retrying'),
      OnlineDuelConnectionState.failed ||
      OnlineDuelConnectionState.closed =>
        context.tr('online_account_unavailable'),
      OnlineDuelConnectionState.connecting => context.tr('connecting_players'),
    };
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.fallbackName,
    required this.ready,
    required this.accent,
    required this.compact,
  });

  final OnlineDuelPlayer? player;
  final String fallbackName;
  final bool ready;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final name = player?.displayName ?? fallbackName;
    return Card(
      color: const Color(0xFF142126).withValues(alpha: .96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: accent.withValues(alpha: .48)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PlayerAvatar(
              displayName: name,
              avatarKey: player?.avatarKey ?? 'prematch-$name',
              radius: compact ? 30 : 40,
              semanticLabel: context.tr(
                'player_avatar_semantics',
                <Object>[name],
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 15 : 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              player == null ? '—' : context.tr('elo_unknown'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: .58),
                fontSize: 13,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Chip(
              avatar: Icon(
                ready ? Icons.check_circle_rounded : Icons.schedule_rounded,
                color: ready ? const Color(0xFF29D398) : accent,
              ),
              label: Text(
                ready
                    ? context.tr('ready')
                    : context.tr('waiting_opponent_ready'),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
