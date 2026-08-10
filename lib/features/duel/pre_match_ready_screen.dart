import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  SocialPlayer? _opponentPublicProfile;
  String? _opponentProfileRequestedFor;
  Object? _error;
  Timer? _retryTimer;
  bool _readyPressed = false;
  bool _screenLoadedSent = false;
  bool _handedOff = false;
  bool _connecting = false;
<<<<<<< HEAD
=======
  bool _leaving = false;
  bool _matchHapticSent = false;
  Timer? _retryTimer;
  int _connectAttempt = 0;
>>>>>>> 57ac512da8bc2fd8e78c3eab5c59e303afa81a83

  @override
  void initState() {
    super.initState();
    _profilePlayer = widget.initialCurrentPlayer;
    if (_profilePlayer == null) unawaited(_loadProfile());
    unawaited(_connect());
  }

  @override
  void dispose() {
    unawaited(_snapshotSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    _retryTimer?.cancel();
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

  Future<void> _loadOpponentPublicProfile(String publicId) async {
    final normalized = publicId.trim();
    if (normalized.length < 3 ||
        normalized == _opponentProfileRequestedFor ||
        _handedOff) {
      return;
    }
    _opponentProfileRequestedFor = normalized;
    try {
      final players = await SocialApiClient.instance.searchPlayers(normalized);
      SocialPlayer? exact;
      for (final player in players) {
        if (player.publicId == normalized) {
          exact = player;
          break;
        }
      }
      if (!mounted || _handedOff) return;
      if (exact != null) {
        setState(() => _opponentPublicProfile = exact);
      }
    } catch (_) {
      // Private/non-discoverable profiles intentionally keep stats hidden.
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
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
      final transport = await WebSocketOnlineDuelTransport.connect(
        widget.roomId,
      );
      final controller = OnlineDuelController(transport)..start();
      final snapshotSubscription = controller.snapshots.listen((snapshot) {
        if (!mounted) return;
        final hadOpponent = _opponent != null;
        final opponentSeat = snapshot.youSeat == OnlineDuelSeat.a
            ? OnlineDuelSeat.b
            : OnlineDuelSeat.a;
        final opponent = snapshot.players[opponentSeat];
        final hasOpponent = opponent != null;
        setState(() {
          _snapshot = snapshot;
          _error = null;
          if (snapshot.players[snapshot.youSeat]?.ready == true) {
            _readyPressed = true;
          }
        });
        if (hasOpponent) {
          unawaited(_loadOpponentPublicProfile(opponent.publicId));
        }
        if (!hadOpponent && hasOpponent && !_matchHapticSent) {
          _matchHapticSent = true;
          unawaited(HapticFeedback.mediumImpact());
        }
        _sendScreenLoaded();
        if (snapshot.status == OnlineDuelStatus.active) {
          unawaited(_openMatch(controller));
        }
      });
      final connectionSubscription = controller.connectionStates.listen((
        state,
      ) {
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
<<<<<<< HEAD
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _handedOff) return;
      unawaited(_connect());
=======
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
>>>>>>> 57ac512da8bc2fd8e78c3eab5c59e303afa81a83
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

<<<<<<< HEAD
=======
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

>>>>>>> 57ac512da8bc2fd8e78c3eab5c59e303afa81a83
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
    final publicProfile = _opponentPublicProfile;
    final profileMatches = publicProfile?.publicId == player.publicId;
    final rating = profileMatches ? publicProfile?.rating : null;
    return MatchmakingVisualPlayer(
      displayName: player.displayName.isEmpty
          ? player.username
          : player.displayName,
      avatarKey: player.avatarKey.isEmpty
          ? 'prematch-${player.publicId}'
          : player.avatarKey,
      rankLabel: rating == null ? null : matchmakingRankLabel(rating),
      gamesPlayed: profileMatches ? publicProfile?.gamesPlayed : null,
      winRate: profileMatches ? publicProfile?.winRate : null,
      rating: rating,
    );
  }

  @override
  Widget build(BuildContext context) {
<<<<<<< HEAD
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: context.tr('cancel_search'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _readyStage
                                ? context.tr('ready_question')
                                : context.tr('finding_opponent_title'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ConnectionBanner(
                      state: _connectionState,
                      error: _error,
                      onRetry: _connecting ? null : _connect,
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final vertical = constraints.maxWidth < 520;
                          final cards = <Widget>[
                            Expanded(
                              child: _PlayerCard(
                                player: _you,
                                fallbackName: context.tr('you'),
                                ready: _youReady,
                                accent: const Color(0xFF29D398),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: vertical ? 0 : 12,
                                vertical: vertical ? 10 : 0,
                              ),
                              child: const Icon(
                                Icons.flash_on_rounded,
                                color: Color(0xFFFFC94D),
                                size: 34,
                              ),
                            ),
                            Expanded(
                              child: _PlayerCard(
                                player: _opponent,
                                fallbackName: context.tr('opponent'),
                                ready: _opponentReady,
                                accent: const Color(0xFF7A5CFF),
                              ),
                            ),
                          ];
                          return vertical
                              ? Column(children: cards)
                              : Row(children: cards);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _statusText(context),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .74),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
=======
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
>>>>>>> 57ac512da8bc2fd8e78c3eab5c59e303afa81a83
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
<<<<<<< HEAD
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
=======
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
>>>>>>> 57ac512da8bc2fd8e78c3eab5c59e303afa81a83
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

<<<<<<< HEAD
class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.fallbackName,
    required this.ready,
    required this.accent,
  });

  final OnlineDuelPlayer? player;
  final String fallbackName;
  final bool ready;
  final Color accent;

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
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PlayerAvatar(
              displayName: name,
              avatarKey: player?.avatarKey ?? 'prematch-$name',
              radius: 40,
              semanticLabel: context.tr('player_avatar_semantics', <Object>[
                name,
              ]),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
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
            const SizedBox(height: 12),
            Chip(
              avatar: Icon(
                ready ? Icons.check_circle_rounded : Icons.schedule_rounded,
                color: ready ? const Color(0xFF29D398) : accent,
              ),
              label: Text(
                ready
                    ? context.tr('ready')
                    : context.tr('waiting_opponent_ready'),
              ),
            ),
          ],
        ),
      ),
    );
  }
=======
@visibleForTesting
String matchmakingRankLabel(int rating) {
  if (rating >= 1800) return 'Master';
  if (rating >= 1500) return 'Platinum';
  if (rating >= 1300) return 'Gold';
  if (rating >= 1100) return 'Silver';
  return 'Bronze';
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
>>>>>>> 57ac512da8bc2fd8e78c3eab5c59e303afa81a83
}
