import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../services/social_api_client.dart';
import 'matchmaking_stage.dart';
import 'online_duel_screen.dart';

class PreMatchReadyScreen extends StatefulWidget {
  const PreMatchReadyScreen({
    super.key,
    required this.roomId,
    this.initialCurrentPlayer,
  });

  final String roomId;
  final MatchmakingVisualPlayer? initialCurrentPlayer;

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
  MatchmakingVisualPlayer? _profilePlayer;
  Object? _error;
  bool _readyPressed = false;
  bool _screenLoadedSent = false;
  bool _handedOff = false;
  bool _allowPop = false;
  bool _connecting = false;
  bool _leaving = false;
  bool _matchHapticSent = false;
  Timer? _retryTimer;
  int _connectAttempt = 0;

  @override
  void initState() {
    super.initState();
    _profilePlayer = widget.initialCurrentPlayer;
    if (_profilePlayer == null) unawaited(_loadProfile());
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

  Future<void> _loadProfile() async {
    try {
      final profile = await SocialApiClient.instance.loadCompetitiveProfile();
      if (!mounted) return;
      setState(() {
        _profilePlayer = MatchmakingVisualPlayer(
          displayName: profile.displayName,
          avatarKey: profile.avatarKey,
          rankLabel: profile.rankName,
          gamesPlayed: profile.wins + profile.losses + profile.draws,
          winRate: profile.winRate,
          rating: profile.currentElo,
        );
      });
    } catch (_) {
      // The room snapshot is authoritative and provides a safe identity fallback.
    }
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
    _screenLoadedSent = false;

    try {
      final transport = await WebSocketOnlineDuelTransport.connect(widget.roomId);
      final controller = OnlineDuelController(transport)..start();
      final snapshotSubscription = controller.snapshots.listen((snapshot) {
        if (!mounted) return;
        final hadOpponent = _opponent != null;
        final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
            ? OnlineDuelSeat.b
            : OnlineDuelSeat.a;
        final hasOpponent = snapshot.players[opponentSeat] != null;
        setState(() {
          _snapshot = snapshot;
          _error = null;
          if (snapshot.players[snapshot.youSeat]?.ready == true) {
            _readyPressed = true;
          }
        });
        if (!hadOpponent && hasOpponent && !_matchHapticSent) {
          _matchHapticSent = true;
          unawaited(HapticFeedback.mediumImpact());
        }
        _sendScreenLoaded();
        if (snapshot.status == OnlineDuelStatus.active) {
          unawaited(_openMatch(controller));
        }
      });
      final connectionSubscription = controller.connectionStates.listen((state) {
        if (!mounted) return;
        setState(() => _connectionState = state);
        if (state == OnlineDuelConnectionState.failed ||
            state == OnlineDuelConnectionState.closed) {
          _scheduleReconnect();
        }
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
        _error = UserSafeError.message(context, error);
        _connectionState = OnlineDuelConnectionState.failed;
      });
      _scheduleReconnect();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _scheduleReconnect() {
    if (!mounted || _handedOff || _retryTimer != null || _leaving) return;
    _connectAttempt++;
    final seconds = switch (_connectAttempt) {
      <= 1 => 1,
      2 => 2,
      3 => 4,
      _ => 6,
    };
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      if (mounted && !_handedOff && !_leaving) unawaited(_connect());
    });
  }

  void _sendScreenLoaded() {
    if (_screenLoadedSent || _snapshot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _screenLoadedSent || _controller == null) return;
      _screenLoadedSent = true;
      _controller!.screenLoaded();
    });
  }

  Future<void> _cancelAndLeave() async {
    if (_leaving || _handedOff || !mounted) return;
    _retryTimer?.cancel();
    setState(() => _leaving = true);
    final controller = _controller;
    controller?.forfeit();
    if (controller != null &&
        (_connectionState == OnlineDuelConnectionState.connected ||
            _connectionState == OnlineDuelConnectionState.resyncing)) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    await _snapshotSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await controller?.dispose();
    _controller = null;
    _snapshotSubscription = null;
    _connectionSubscription = null;
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  void _ready() {
    if (_readyPressed || _controller == null || !_readyStage) return;
    setState(() => _readyPressed = true);
    _controller!.ready();
  }

  Future<void> _openMatch(OnlineDuelController controller) async {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    _retryTimer?.cancel();
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

  MatchmakingVisualPlayer _currentVisualPlayer(BuildContext context) {
    final base = _profilePlayer;
    final roomPlayer = _you;
    if (roomPlayer == null) {
      return base ?? MatchmakingVisualPlayer(displayName: context.tr('you'));
    }
    return MatchmakingVisualPlayer(
      displayName: roomPlayer.displayName.isEmpty
          ? (base?.displayName ?? context.tr('you'))
          : roomPlayer.displayName,
      avatarKey: roomPlayer.avatarKey.isEmpty
          ? (base?.avatarKey ?? 'prematch-you')
          : roomPlayer.avatarKey,
      remoteApprovedImageUrl: base?.remoteApprovedImageUrl,
      rankLabel: base?.rankLabel,
      gamesPlayed: base?.gamesPlayed,
      winRate: base?.winRate,
      rating: base?.rating,
    );
  }

  MatchmakingVisualPlayer? _opponentVisualPlayer() {
    final player = _opponent;
    if (player == null) return null;
    return MatchmakingVisualPlayer(
      displayName: player.displayName.isEmpty ? player.username : player.displayName,
      avatarKey: player.avatarKey.isEmpty
          ? 'prematch-${player.publicId}'
          : player.avatarKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = _connectionState == OnlineDuelConnectionState.failed ||
        _connectionState == OnlineDuelConnectionState.closed ||
        _error != null;
    final opponent = _opponentVisualPlayer();
    final action = _actionForState(context, failed);

    return PopScope(
      canPop: _handedOff || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancelAndLeave());
      },
      child: MatchmakingStage(
        currentPlayer: _currentVisualPlayer(context),
        opponent: opponent,
        searching: opponent == null,
        searchStatus: failed
            ? context.tr('online_account_unavailable')
            : _connectionLabel(context),
        opponentStatus: _opponentReady
            ? context.tr('opponent_ready')
            : _connectionLabel(context),
        opponentReady: _opponentReady,
        actionLabel: action.label,
        actionIcon: action.icon,
        actionBusy: _leaving || _connecting || action.busy,
        onAction: _leaving ? null : action.onPressed,
        onClose: _leaving ? null : _cancelAndLeave,
      ),
    );
  }

  _StageAction _actionForState(BuildContext context, bool failed) {
    if (failed) {
      return _StageAction(
        label: context.tr('retry'),
        icon: Icons.refresh_rounded,
        onPressed: _connecting ? null : () => unawaited(_connect()),
      );
    }
    if (!_readyStage || _controller == null) {
      return _StageAction(
        label: context.tr('connecting_players'),
        icon: Icons.sync_rounded,
        busy: true,
      );
    }
    if (_youReady && _opponentReady) {
      return _StageAction(
        label: context.tr('everyone_ready_starting'),
        icon: Icons.play_arrow_rounded,
        busy: true,
      );
    }
    if (_youReady) {
      return _StageAction(
        label: context.tr('waiting_opponent_ready'),
        icon: Icons.hourglass_top_rounded,
        busy: true,
      );
    }
    return _StageAction(
      label: context.tr('i_am_ready'),
      icon: Icons.play_arrow_rounded,
      onPressed: _ready,
    );
  }

  String _connectionLabel(BuildContext context) {
    if (_error != null) return context.tr('online_account_unavailable');
    return switch (_connectionState) {
      OnlineDuelConnectionState.connected => context.tr('connected'),
      OnlineDuelConnectionState.reconnecting => context.tr('reconnecting'),
      OnlineDuelConnectionState.resyncing =>
        context.tr('connection_interrupted_retrying'),
      OnlineDuelConnectionState.failed || OnlineDuelConnectionState.closed =>
        context.tr('online_account_unavailable'),
      OnlineDuelConnectionState.connecting => context.tr('connecting_players'),
    };
  }
}

class _StageAction {
  const _StageAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
}
