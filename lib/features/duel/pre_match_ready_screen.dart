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
    final statusSubtitle = bothReady
        ? '2/2 players ready'
        : currentReady
        ? '$readyCount/2 players ready'
        : 'Both players need to be ready to start';

    return Scaffold(
      backgroundColor: const Color(0xFF06111F),
      body: AppBackdrop(
        dim: .20,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 740;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      compact ? 6 : 10,
                      12,
                      compact ? 8 : 12,
                    ),
                    child: Column(
                      children: [
                        _ReadyDuelHeader(
                          opponent: opponent,
                          currentPlayer: currentPlayer,
                          opponentReady: opponentReady,
                          currentReady: currentReady,
                        ),
                        SizedBox(height: compact ? 7 : 10),
                        Expanded(
                          child: _ReadyVersusArena(
                            currentPlayer: currentPlayer,
                            opponent: opponent,
                            currentReady: currentReady,
                            opponentReady: opponentReady,
                            compact: compact,
                          ),
                        ),
                        SizedBox(height: compact ? 7 : 10),
                        _ReadyStatusCard(
                          title: statusTitle,
                          subtitle: statusSubtitle,
                          readyCount: readyCount,
                        ),
                        SizedBox(height: compact ? 8 : 11),
                        SizedBox(
                          width: double.infinity,
                          height: compact ? 58 : 66,
                          child: FilledButton.icon(
                            key: const ValueKey<String>('prematch-ready-action'),
                            onPressed: actionBusy ? null : onAction,
                            icon: actionBusy
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF29D398),
                                        width: 2,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(actionIcon, size: 25),
                                  ),
                            label: Text(
                              actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xD9102830),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xC5132430),
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                                side: const BorderSide(
                                  color: Color(0xFF29D398),
                                  width: 1.6,
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
                            const Spacer(),
                            SizedBox(
                              width: 58,
                              height: 58,
                              child: IconButton(
                                tooltip: context.tr('cancel'),
                                onPressed: onClose,
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xD8142430),
                                  foregroundColor: const Color(0xFFFFC94D),
                                  side: BorderSide(
                                    color: const Color(0xFFFFC94D)
                                        .withValues(alpha: .44),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.tune_rounded,
                                  size: 25,
                                ),
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

class _ReadyDuelHeader extends StatelessWidget {
  const _ReadyDuelHeader({
    required this.opponent,
    required this.currentPlayer,
    required this.opponentReady,
    required this.currentReady,
  });

  final MatchmakingVisualPlayer? opponent;
  final MatchmakingVisualPlayer currentPlayer;
  final bool opponentReady;
  final bool currentReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xDA0C1A2A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MiniPlayerHeader(
              player: opponent,
              fallbackName: context.tr('opponent'),
              accent: const Color(0xFF3AA9FF),
              ready: opponentReady,
            ),
          ),
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF17263A),
              border: Border.all(
                color: const Color(0xFF29D398).withValues(alpha: .72),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF29D398).withValues(alpha: .18),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(opponentReady ? 1 : 0) + (currentReady ? 1 : 0)}/2',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'READY',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .48),
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _MiniPlayerHeader(
              player: currentPlayer,
              fallbackName: context.tr('you'),
              accent: const Color(0xFFFFC94D),
              ready: currentReady,
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayerHeader extends StatelessWidget {
  const _MiniPlayerHeader({
    required this.player,
    required this.fallbackName,
    required this.accent,
    required this.ready,
    this.alignEnd = false,
  });

  final MatchmakingVisualPlayer? player;
  final String fallbackName;
  final Color accent;
  final bool ready;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final name = p?.displayName.isNotEmpty == true ? p!.displayName : fallbackName;
    final avatar = p == null
        ? Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF122236),
              border: Border.all(color: accent.withValues(alpha: .56)),
            ),
            child: const Icon(Icons.person_outline_rounded, color: Colors.white54),
          )
        : Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: ready ? 2 : 1),
              boxShadow: ready
                  ? [BoxShadow(color: accent.withValues(alpha: .28), blurRadius: 10)]
                  : null,
            ),
            child: PlayerAvatar(
              displayName: p.displayName,
              avatarKey: p.avatarKey,
              radius: 19,
              semanticLabel: p.displayName,
            ),
          );
    final info = Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            p?.rankLabel ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFC3A8FF),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${p?.rating ?? 0} RP',
            style: TextStyle(
              color: ready ? const Color(0xFF29D398) : Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Row(
        textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
        children: [avatar, const SizedBox(width: 7), info],
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
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ReadyArenaPainter(),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: .92,
                  heightFactor: compact ? .86 : .88,
                  child: _ReadyPlayerCard(
                    player: opponent,
                    ready: opponentReady,
                    accent: const Color(0xFF3AA9FF),
                    placeholderLabel: context.tr('connecting_players'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: .92,
                  heightFactor: compact ? .86 : .88,
                  child: _ReadyPlayerCard(
                    player: currentPlayer,
                    ready: currentReady,
                    accent: const Color(0xFFFFC94D),
                    placeholderLabel: context.tr('you'),
                  ),
                ),
              ),
            ),
          ],
        ),
        Container(
          width: compact ? 58 : 66,
          height: compact ? 58 : 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF16263A),
            border: Border.all(
              color: const Color(0xFFFFC94D).withValues(alpha: .50),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3AA9FF).withValues(alpha: .34),
                blurRadius: 20,
                offset: const Offset(-8, 0),
              ),
              BoxShadow(
                color: const Color(0xFFFFC94D).withValues(alpha: .30),
                blurRadius: 20,
                offset: const Offset(8, 0),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.shield_rounded,
            color: Color(0xFFFFC94D),
            size: 33,
          ),
        ),
      ],
    );
  }
}

class _ReadyPlayerCard extends StatelessWidget {
  const _ReadyPlayerCard({
    required this.player,
    required this.ready,
    required this.accent,
    required this.placeholderLabel,
  });

  final MatchmakingVisualPlayer? player;
  final bool ready;
  final Color accent;
  final String placeholderLabel;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF0162940), Color(0xF10A1624)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: .74), width: 1.35),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: ready ? .27 : .14),
            blurRadius: ready ? 24 : 16,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .33),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: p == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF102139),
                    border: Border.all(color: accent.withValues(alpha: .60), width: 2),
                  ),
                  child: const Icon(Icons.person_search_rounded, color: Colors.white54, size: 42),
                ),
                const SizedBox(height: 18),
                Text(
                  placeholderLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
                ),
              ],
            )
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2.2),
                    boxShadow: [
                      BoxShadow(color: accent.withValues(alpha: .28), blurRadius: 18),
                    ],
                  ),
                  child: PlayerAvatar(
                    displayName: p.displayName,
                    avatarKey: p.avatarKey,
                    radius: 34,
                    semanticLabel: p.displayName,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  p.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  p.rankLabel ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFC3A8FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Divider(color: Colors.white.withValues(alpha: .16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _ReadyStat(value: '${p.gamesPlayed ?? 0}', label: 'Matches')),
                    Expanded(
                      child: _ReadyStat(
                        value: '${(((p.winRate ?? 0) * 100).round())}%',
                        label: 'Win rate',
                      ),
                    ),
                    Expanded(child: _ReadyStat(value: '${p.rating ?? 0}', label: 'RP', accent: true)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      ready ? Icons.check_circle_rounded : Icons.link_rounded,
                      color: ready ? const Color(0xFF29D398) : const Color(0xFF66C7FF),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ready ? context.tr('ready') : context.tr('connected'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
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
          style: TextStyle(
            color: accent ? const Color(0xFFC3A8FF) : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .52),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xD9102030),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF122C44),
              border: Border.all(color: const Color(0xFF66C7FF).withValues(alpha: .42)),
            ),
            child: const Icon(Icons.group_rounded, color: Colors.white, size: 24),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: readyCount == 2 ? const Color(0xFF29D398) : const Color(0xFFFFC94D),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (readyCount == 2 ? const Color(0xFF29D398) : const Color(0xFFFFC94D))
                      .withValues(alpha: .34),
                  blurRadius: 9,
                ),
              ],
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
    final blue = Paint()
      ..color = const Color(0xFF2BA9FF).withValues(alpha: .20)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final gold = Paint()
      ..color = const Color(0xFFFFC94D).withValues(alpha: .18)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (var i = 1; i <= 3; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: size.width * (.32 + i * .15),
          height: size.height * (.20 + i * .11),
        ),
        i.isOdd ? blue : gold,
      );
    }

    final bolt = Path()
      ..moveTo(center.dx - 10, size.height * .34)
      ..lineTo(center.dx + 15, size.height * .45)
      ..lineTo(center.dx - 9, size.height * .53)
      ..lineTo(center.dx + 12, size.height * .64);
    final glow = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3AA9FF), Color(0xFFFFC94D)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(bolt, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
