import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/user_safe_error.dart';
import '../../localization/app_strings.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_emote_hub.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../services/rank_identity_service.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/player_avatar.dart';
import 'matchmaking_stage.dart';
import 'online_duel_screen.dart';

class PreMatchReadyScreen extends StatefulWidget {
  const PreMatchReadyScreen({
    super.key,
    required this.roomId,
    this.initialCurrentPlayer,
    this.controller,
  });

  final String roomId;
  final MatchmakingVisualPlayer? initialCurrentPlayer;
  final OnlineDuelController? controller;

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
  PublicRankSummary? _opponentPublicProfile;
  String? _opponentProfileRequestedFor;
  Object? _error;
  bool _readyPressed = false;
  bool _screenLoadedSent = false;
  bool _autoReadySent = false;
  bool _handedOff = false;
  bool _allowPop = false;
  bool _connecting = false;
  bool _leaving = false;
  bool _matchHapticSent = false;
  Timer? _retryTimer;
  Timer? _autoReadyTimer;
  int _connectAttempt = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCurrentPlayer;
    _profilePlayer = initial == null
        ? null
        : MatchmakingVisualPlayer(
            displayName: initial.displayName,
            avatarKey: initial.avatarKey,
            remoteApprovedImageUrl: initial.remoteApprovedImageUrl,
            gamesPlayed: initial.gamesPlayed,
            winRate: initial.winRate,
          );
    unawaited(_loadProfile());
    unawaited(_connect());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _autoReadyTimer?.cancel();
    unawaited(_snapshotSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    if (!_handedOff) unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await RankIdentityService.instance.refresh();
      if (!mounted) return;
      final stats = profile.stats;
      final winRate = stats.rankedGames == 0
          ? 0.0
          : stats.wins / stats.rankedGames;
      setState(() {
        _profilePlayer = MatchmakingVisualPlayer(
          displayName: profile.displayName,
          avatarKey: profile.avatarKey,
          rankLabel: profile.rankName,
          gamesPlayed: stats.rankedGames,
          winRate: winRate,
          // Legacy presentation slot, now populated with visible RP only.
          rating: profile.rankPoints,
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
      final exact = await RankIdentityService.instance.loadPublicRankSummary(
        normalized,
      );
      if (!mounted || _handedOff) return;
      setState(() => _opponentPublicProfile = exact);
    } catch (_) {
      // Private/non-discoverable profiles intentionally keep RP stats hidden.
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
    if (!identical(_controller, widget.controller)) {
      await _controller?.dispose();
    }
    _controller = null;
    _screenLoadedSent = false;
    _autoReadySent = false;
    _autoReadyTimer?.cancel();
    _autoReadyTimer = null;

    try {
      final injectedController = widget.controller;
      final controller =
          injectedController ??
          OnlineDuelController(
            await WebSocketOnlineDuelTransport.connect(widget.roomId),
          );
      controller.start();
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
        _scheduleAutoReady();
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
      _connectAttempt = 0;
      setState(() {
        _controller = controller;
        _snapshotSubscription = snapshotSubscription;
        _connectionSubscription = connectionSubscription;
        _connectionState = controller.connectionState;
      });
      controller.requestSnapshot();
    } catch (error, stackTrace) {
      debugPrint('Pre-match room connection failed: $error');
      debugPrintStack(stackTrace: stackTrace);
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

  void _scheduleAutoReady() {
    if (_autoReadySent ||
        _autoReadyTimer != null ||
        _controller == null ||
        !_readyStage ||
        _youReady) {
      return;
    }
    _autoReadyTimer = Timer(const Duration(seconds: 10), () {
      _autoReadyTimer = null;
      if (!mounted ||
          _autoReadySent ||
          _controller == null ||
          !_readyStage ||
          _youReady) {
        return;
      }
      _autoReadySent = true;
      setState(() => _readyPressed = true);
      _controller!.ready();
    });
  }

  Future<void> _cancelAndLeave() async {
    if (_leaving || _handedOff || !mounted) return;
    _retryTimer?.cancel();
    _autoReadyTimer?.cancel();
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
    _autoReadyTimer?.cancel();
    _autoReadyTimer = null;
    setState(() => _readyPressed = true);
    _controller!.ready();
  }

  Future<void> _openMatch(OnlineDuelController controller) async {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    _retryTimer?.cancel();
    _autoReadyTimer?.cancel();
    await _snapshotSubscription?.cancel();
    await _connectionSubscription?.cancel();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement<String?, void>(
      MaterialPageRoute(
        builder: (_) =>
            OnlineDuelScreen(roomId: widget.roomId, controller: controller),
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
    final matchedProfile = publicProfile?.publicId == player.publicId
        ? publicProfile
        : null;
    final matchedAvatarKey = matchedProfile?.avatarKey;
    return MatchmakingVisualPlayer(
      displayName: player.displayName.isEmpty
          ? player.username
          : player.displayName,
      avatarKey: matchedAvatarKey != null && matchedAvatarKey.isNotEmpty
          ? matchedAvatarKey
          : player.avatarKey.isEmpty
          ? 'prematch-${player.publicId}'
          : player.avatarKey,
      rankLabel: matchedProfile?.rankName,
      gamesPlayed: matchedProfile?.gamesPlayed,
      winRate: matchedProfile?.winRate,
      rating: matchedProfile?.rankPoints,
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed =
        _connectionState == OnlineDuelConnectionState.failed ||
        _connectionState == OnlineDuelConnectionState.closed ||
        _error != null;
    final opponent = _opponentVisualPlayer();
    final action = _actionForState(context, failed);

    return PopScope(
      canPop: _handedOff || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancelAndLeave());
      },
      child: _ReadyArenaStage(
        currentPlayer: _currentVisualPlayer(context),
        opponent: opponent,
        currentReady: _youReady,
        opponentReady: _opponentReady,
        connectionLabel: failed
            ? context.tr('online_account_unavailable')
            : _connectionLabel(context),
        actionLabel: action.label,
        actionIcon: action.icon,
        actionBusy: _leaving || _connecting || action.busy,
        onAction: _leaving ? null : action.onPressed,
        onClose: _leaving ? null : _cancelAndLeave,
        floatingControl: _showReadyEmotes
            ? const OnlineDuelInlineEmoteSurface(
                key: ValueKey<String>('ready-screen-emotes'),
                compact: true,
                accent: Color(0xFFFFC94D),
              )
            : null,
      ),
    );
  }

  bool get _showReadyEmotes {
    final opponent = _opponent;
    final status = _snapshot?.status;
    return opponent != null &&
        opponent.publicId.trim().isNotEmpty &&
        status != null &&
        onlineDuelStatusAllowsEmotes(status) &&
        _connectionState == OnlineDuelConnectionState.connected;
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
      OnlineDuelConnectionState.resyncing => context.tr(
        'connection_interrupted_retrying',
      ),
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

class _ReadyArenaStage extends StatelessWidget {
  const _ReadyArenaStage({
    required this.currentPlayer,
    required this.opponent,
    required this.currentReady,
    required this.opponentReady,
    required this.connectionLabel,
    required this.actionLabel,
    required this.actionIcon,
    required this.actionBusy,
    required this.onAction,
    required this.onClose,
    required this.floatingControl,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer? opponent;
  final bool currentReady;
  final bool opponentReady;
  final String connectionLabel;
  final String actionLabel;
  final IconData actionIcon;
  final bool actionBusy;
  final VoidCallback? onAction;
  final VoidCallback? onClose;
  final Widget? floatingControl;

  @override
  Widget build(BuildContext context) {
    final readyCount = (currentReady ? 1 : 0) + (opponentReady ? 1 : 0);
    final bothReady = readyCount == 2;
    final statusTitle = bothReady
        ? context.tr('everyone_ready_starting')
        : currentReady
        ? context.tr('waiting_opponent_ready')
        : 'Waiting for both players to confirm';
    final statusSubtitle = currentReady
        ? '$readyCount/2 players ready'
        : connectionLabel;

    return Scaffold(
      backgroundColor: const Color(0xFF07111E),
      body: AppBackdrop(
        dim: .28,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      compact ? 8 : 12,
                      14,
                      compact ? 10 : 16,
                    ),
                    child: Column(
                      children: [
                        _ReadyTopBar(onClose: onClose),
                        SizedBox(height: compact ? 8 : 12),
                        Expanded(
                          child: _ReadyVersusArena(
                            currentPlayer: currentPlayer,
                            opponent: opponent,
                            currentReady: currentReady,
                            opponentReady: opponentReady,
                            compact: compact,
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        _ReadyStatusCard(
                          title: statusTitle,
                          subtitle: statusSubtitle,
                          readyCount: readyCount,
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        SizedBox(
                          width: double.infinity,
                          height: compact ? 54 : 62,
                          child: FilledButton.icon(
                            key: const ValueKey<String>('prematch-ready-action'),
                            onPressed: actionBusy ? null : onAction,
                            icon: actionBusy
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Icon(actionIcon, size: 25),
                            label: Text(
                              actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0D463E),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(
                                0xFF132733,
                              ),
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                                side: BorderSide(
                                  color: const Color(
                                    0xFF29D398,
                                  ).withValues(alpha: .86),
                                ),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 7 : 10),
                        Row(
                          children: [
                            SizedBox(
                              width: 58,
                              height: 58,
                              child: Center(
                                child: floatingControl ??
                                    const SizedBox.shrink(),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'The match will begin once both players are ready.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .52),
                                  fontSize: compact ? 10 : 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 58,
                              height: 58,
                              child: IconButton(
                                tooltip: context.tr('cancel'),
                                onPressed: onClose,
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFF152431,
                                  ).withValues(alpha: .94),
                                  foregroundColor: const Color(0xFFFFC94D),
                                  side: BorderSide(
                                    color: const Color(
                                      0xFFFFC94D,
                                    ).withValues(alpha: .26),
                                  ),
                                ),
                                icon: const Icon(Icons.more_horiz_rounded),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReadyTopBar extends StatelessWidget {
  const _ReadyTopBar({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          IconButton(
            tooltip: context.tr('cancel'),
            onPressed: onClose,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF15324A).withValues(alpha: .88),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 27),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('online_duel').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'READY CHECK',
                  style: TextStyle(
                    color: const Color(0xFF66C7FF).withValues(alpha: .82),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyVersusArena extends StatelessWidget {
  const _ReadyVersusArena({
    required this.currentPlayer,
    required this.opponent,
    required this.currentReady,
    required this.opponentReady,
    required this.compact,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer? opponent;
  final bool currentReady;
  final bool opponentReady;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xE8112233), Color(0xED08131E)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF66C7FF).withValues(alpha: .25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .30),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _ReadyArenaPainter())),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 16,
                compact ? 12 : 18,
                compact ? 10 : 16,
                compact ? 12 : 18,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ReadyPlayerCard(
                      player: opponent,
                      ready: opponentReady,
                      accent: const Color(0xFF3AA9FF),
                      compact: compact,
                      placeholderLabel: context.tr('connecting_players'),
                    ),
                  ),
                  SizedBox(
                    width: compact ? 54 : 70,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: compact ? 46 : 58,
                          height: compact ? 46 : 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFF27435C), Color(0xFF0A1722)],
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFFFFC94D,
                              ).withValues(alpha: .48),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF3AA9FF,
                                ).withValues(alpha: .24),
                                blurRadius: 18,
                              ),
                              BoxShadow(
                                color: const Color(
                                  0xFFFFC94D,
                                ).withValues(alpha: .15),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Text(
                            'VS',
                            style: TextStyle(
                              color: const Color(0xFFFFD66B),
                              fontSize: compact ? 17 : 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _ReadyPlayerCard(
                      player: currentPlayer,
                      ready: currentReady,
                      accent: const Color(0xFFFFC94D),
                      compact: compact,
                      placeholderLabel: context.tr('you'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyPlayerCard extends StatelessWidget {
  const _ReadyPlayerCard({
    required this.player,
    required this.ready,
    required this.accent,
    required this.compact,
    required this.placeholderLabel,
  });

  final MatchmakingVisualPlayer? player;
  final bool ready;
  final Color accent;
  final bool compact;
  final String placeholderLabel;

  @override
  Widget build(BuildContext context) {
    final value = player;
    final name = value?.displayName.trim().isNotEmpty == true
        ? value!.displayName
        : placeholderLabel;
    final rank = value?.rankLabel?.trim().isNotEmpty == true
        ? value!.rankLabel!
        : '—';
    final games = value?.gamesPlayed ?? 0;
    final winRate = ((value?.winRate ?? 0) * 100).round();
    final rp = value?.rating ?? 0;
    final avatarRadius = compact ? 37.0 : 44.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 12,
        compact ? 12 : 16,
        compact ? 8 : 12,
        compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B29).withValues(alpha: .88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (ready ? const Color(0xFF29D398) : accent).withValues(
            alpha: ready ? .72 : .48,
          ),
          width: ready ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (ready ? const Color(0xFF29D398) : accent).withValues(
              alpha: ready ? .18 : .10,
            ),
            blurRadius: ready ? 20 : 12,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (value == null)
            Container(
              width: avatarRadius * 2,
              height: avatarRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .05),
                border: Border.all(color: accent.withValues(alpha: .28)),
              ),
              child: Center(
                child: SizedBox.square(
                  dimension: compact ? 25 : 30,
                  child: const CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .24),
                    blurRadius: 17,
                  ),
                ],
              ),
              child: PlayerAvatar(
                displayName: name,
                avatarKey: value.avatarKey,
                remoteApprovedImageUrl: value.remoteApprovedImageUrl,
                radius: avatarRadius,
              ),
            ),
          SizedBox(height: compact ? 7 : 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rank,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFFB7A9FF),
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: compact ? 7 : 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: (ready ? const Color(0xFF29D398) : Colors.white)
                  .withValues(alpha: ready ? .12 : .055),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (ready ? const Color(0xFF29D398) : Colors.white)
                    .withValues(alpha: ready ? .40 : .10),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ready ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                  size: 14,
                  color: ready
                      ? const Color(0xFF29D398)
                      : Colors.white.withValues(alpha: .55),
                ),
                const SizedBox(width: 5),
                Text(
                  ready ? context.tr('ready').toUpperCase() : 'WAITING',
                  style: TextStyle(
                    color: ready
                        ? const Color(0xFF29D398)
                        : Colors.white.withValues(alpha: .58),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .65,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 9 : 13),
          Divider(color: Colors.white.withValues(alpha: .10), height: 1),
          SizedBox(height: compact ? 8 : 10),
          Row(
            children: [
              Expanded(child: _ReadyStat(value: '$games', label: 'Matches')),
              Expanded(child: _ReadyStat(value: '$winRate%', label: 'Win rate')),
              Expanded(child: _ReadyStat(value: '$rp', label: 'RP', accent: true)),
            ],
          ),
          SizedBox(height: compact ? 8 : 11),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.link_rounded,
                size: 15,
                color: Color(0xFF66C7FF),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  value == null ? 'Connecting…' : context.tr('connected'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF66C7FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadyStat extends StatelessWidget {
  const _ReadyStat({required this.value, required this.label, this.accent = false});

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: accent ? const Color(0xFFB7A9FF) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .46),
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ReadyStatusCard extends StatelessWidget {
  const _ReadyStatusCard({
    required this.title,
    required this.subtitle,
    required this.readyCount,
  });

  final String title;
  final String subtitle;
  final int readyCount;

  @override
  Widget build(BuildContext context) {
    final complete = readyCount >= 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B29).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF29D398).withValues(alpha: .10),
              border: Border.all(
                color: const Color(0xFF29D398).withValues(alpha: .35),
              ),
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.people_alt_rounded,
              color: const Color(0xFF29D398),
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .50),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$readyCount/2',
            style: TextStyle(
              color: complete
                  ? const Color(0xFF29D398)
                  : const Color(0xFF66C7FF),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyArenaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF3AA9FF).withValues(alpha: .09);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, i * size.shortestSide * .095, ring);
    }

    final line = Paint()
      ..strokeWidth = 1.1
      ..shader = const LinearGradient(
        colors: [Color(0x003AA9FF), Color(0xAA3AA9FF), Color(0x00FFC94D)],
      ).createShader(Offset.zero & size);
    canvas.drawLine(
      Offset(size.width * .27, size.height * .50),
      Offset(size.width * .73, size.height * .50),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
