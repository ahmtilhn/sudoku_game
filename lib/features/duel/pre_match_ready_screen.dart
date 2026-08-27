import 'dart:async';
import 'dart:math' as math;

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
            rankLabel: initial.rankLabel,
            gamesPlayed: initial.gamesPlayed,
            winRate: initial.winRate,
            rating: initial.rating,
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
      // Room identity remains usable if the optional rank read fails.
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
      // Private/non-discoverable profiles intentionally keep public stats hidden.
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

  Future<void> _confirmCancelAndLeave() async {
    if (_leaving || _handedOff || !mounted) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave ready room?'),
        content: const Text(
          'You will leave this duel room. The match will not start from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('stay')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave room'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) await _cancelAndLeave();
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

  String get _difficultyLabel {
    final raw = _snapshot?.difficulty.trim() ?? '';
    if (raw.isEmpty) return 'Duel';
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

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
    final currentPlayer = _currentVisualPlayer(context);
    final opponent = _opponentVisualPlayer();
    final action = _actionForState(context, failed);
    final showOpponentFound =
        !failed && _readyStage && opponent != null && !_youReady;

    return PopScope(
      canPop: _handedOff || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmCancelAndLeave());
      },
      child: showOpponentFound
          ? _OpponentFoundStage(
              currentPlayer: currentPlayer,
              opponent: opponent,
              opponentReady: _opponentReady,
              difficultyLabel: _difficultyLabel,
              actionBusy: _leaving || _connecting,
              onReady: _leaving ? null : _ready,
              onLeave: _leaving ? null : _confirmCancelAndLeave,
              floatingControl: _showReadyEmotes
                  ? const OnlineDuelInlineEmoteSurface(
                      key: ValueKey<String>('opponent-found-emotes'),
                      compact: true,
                      accent: Color(0xFFFFC94D),
                    )
                  : null,
            )
          : _ReadyArenaStage(
              currentPlayer: currentPlayer,
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
              onLeave: _leaving ? null : _confirmCancelAndLeave,
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
    final connectionUsable =
        _connectionState == OnlineDuelConnectionState.connected ||
        _connectionState == OnlineDuelConnectionState.resyncing;
    return opponent != null &&
        opponent.publicId.trim().isNotEmpty &&
        status != null &&
        onlineDuelStatusAllowsEmotes(status) &&
        connectionUsable;
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

class _OpponentFoundStage extends StatelessWidget {
  const _OpponentFoundStage({
    required this.currentPlayer,
    required this.opponent,
    required this.opponentReady,
    required this.difficultyLabel,
    required this.actionBusy,
    required this.onReady,
    required this.onLeave,
    this.floatingControl,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer opponent;
  final bool opponentReady;
  final String difficultyLabel;
  final bool actionBusy;
  final VoidCallback? onReady;
  final VoidCallback? onLeave;
  final Widget? floatingControl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050D17),
      body: AppBackdrop(
        dim: .48,
        child: SafeArea(
          minimum: const EdgeInsets.only(top: 2, bottom: 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final horizontalScale = (width / 390).clamp(.84, 1.10).toDouble();
              final verticalScale = (height / 800).clamp(.78, 1.06).toDouble();
              final scale = math.min(horizontalScale, verticalScale).toDouble();
              final sidePadding = (20 * horizontalScale)
                  .clamp(14.0, 24.0)
                  .toDouble();

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      sidePadding,
                      5 * scale,
                      sidePadding,
                      8 * scale,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FoundHeader(
                          difficultyLabel: difficultyLabel,
                          onBack: onLeave,
                          scale: scale,
                        ),
                        SizedBox(height: 8 * scale),
                        _FoundTitle(scale: scale),
                        SizedBox(height: 14 * scale),
                        Expanded(
                          child: _FoundDuelArena(
                            currentPlayer: currentPlayer,
                            opponent: opponent,
                            opponentReady: opponentReady,
                            scale: scale,
                          ),
                        ),
                        SizedBox(height: 12 * scale),
                        _FoundStatusCard(
                          opponentName: opponent.displayName,
                          opponentReady: opponentReady,
                          scale: scale,
                        ),
                        SizedBox(height: 12 * scale),
                        SizedBox(
                          width: double.infinity,
                          height: (56 * scale).clamp(50.0, 60.0).toDouble(),
                          child: FilledButton.icon(
                            onPressed: actionBusy ? null : onReady,
                            icon: actionBusy
                                ? const SizedBox.square(
                                    dimension: 19,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF29D398),
                                        width: 1.7,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 21,
                                    ),
                                  ),
                            label: Text(
                              context.tr('i_am_ready'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: (16 * scale)
                                    .clamp(14.0, 17.0)
                                    .toDouble(),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xE60B2730),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xC5132430),
                              disabledForegroundColor: Colors.white70,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: const BorderSide(
                                  color: Color(0xFF29D398),
                                  width: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 8 * scale),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            ?floatingControl,
                            const Spacer(),
                            _ReadyOptionsButton(onLeave: onLeave),
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

class _FoundHeader extends StatelessWidget {
  const _FoundHeader({
    required this.difficultyLabel,
    required this.onBack,
    required this.scale,
  });

  final String difficultyLabel;
  final VoidCallback? onBack;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final buttonSize = (46 * scale).clamp(40.0, 50.0).toDouble();
    return SizedBox(
      height: (52 * scale).clamp(46.0, 56.0).toDouble(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(
              dimension: buttonSize,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onBack,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xC70B1A29),
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: const Color(0xFF3AA9FF).withValues(alpha: .23),
                  ),
                ),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: (21 * scale).clamp(18.0, 22.0).toDouble(),
                ),
              ),
            ),
          ),
          Text(
            difficultyLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: (21 * scale).clamp(18.0, 23.0).toDouble(),
              fontWeight: FontWeight.w900,
              letterSpacing: -.35,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: const Color(0xC70B1A29),
                borderRadius: BorderRadius.circular(buttonSize * .34),
                border: Border.all(
                  color: const Color(0xFF29D398).withValues(alpha: .25),
                ),
              ),
              child: const Icon(Icons.check_rounded, color: Color(0xFF29D398)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoundTitle extends StatelessWidget {
  const _FoundTitle({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: const Color(0xFF29D398),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF29D398).withValues(alpha: .28),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        SizedBox(width: 8 * scale),
        Text(
          'Opponent found',
          style: TextStyle(
            color: Colors.white,
            fontSize: (14 * scale).clamp(12.0, 15.0).toDouble(),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _FoundDuelArena extends StatelessWidget {
  const _FoundDuelArena({
    required this.currentPlayer,
    required this.opponent,
    required this.opponentReady,
    required this.scale,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer opponent;
  final bool opponentReady;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final arenaWidth = constraints.maxWidth;
        final arenaHeight = constraints.maxHeight;
        final visualHeight = math.min(arenaHeight, 375 * scale).toDouble();
        final centerGap = (arenaWidth * .075).clamp(28.0, 40.0).toDouble();
        final cardWidth = ((arenaWidth - centerGap) / 2)
            .clamp(118.0, 232.0)
            .toDouble();

        return Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 7 * (1 - value)),
                child: Transform.scale(
                  scale: .988 + .012 * value,
                  child: child,
                ),
              ),
            ),
            child: SizedBox(
              width: arenaWidth,
              height: visualHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: .78,
                          colors: [
                            const Color(0xFF12304A).withValues(alpha: .18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: cardWidth,
                      height: visualHeight,
                      child: _FoundPlayerCard(
                        player: currentPlayer,
                        accent: const Color(0xFF2FB6FF),
                        sideLabel: context.tr('you'),
                        ready: false,
                        scale: scale,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: cardWidth,
                      height: visualHeight,
                      child: _FoundPlayerCard(
                        player: opponent,
                        accent: const Color(0xFFFFC94D),
                        sideLabel: context.tr('opponent'),
                        ready: opponentReady,
                        scale: scale,
                      ),
                    ),
                  ),
                  _FoundVersusBadge(scale: scale),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FoundPlayerCard extends StatelessWidget {
  const _FoundPlayerCard({
    required this.player,
    required this.accent,
    required this.sideLabel,
    required this.ready,
    required this.scale,
  });

  final MatchmakingVisualPlayer player;
  final Color accent;
  final String sideLabel;
  final bool ready;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 300;
        final veryDense = constraints.maxHeight < 245;
        final radius = veryDense
            ? 25.0
            : dense
            ? 30.0
            : (39 * scale).clamp(34.0, 43.0).toDouble();

        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xF1122639), Color(0xF2071420)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accent.withValues(alpha: .80),
              width: 1.35,
            ),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: .14), blurRadius: 20),
              BoxShadow(
                color: Colors.black.withValues(alpha: .34),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              (11 * scale).clamp(8.0, 13.0).toDouble(),
              (12 * scale).clamp(9.0, 14.0).toDouble(),
              (11 * scale).clamp(8.0, 13.0).toDouble(),
              (11 * scale).clamp(8.0, 13.0).toDouble(),
            ),
            child: Column(
              children: [
                Text(
                  sideLabel.toUpperCase(),
                  style: TextStyle(
                    color: accent.withValues(alpha: .70),
                    fontSize: dense ? 7 : 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 1.8),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .22),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: PlayerAvatar(
                    displayName: player.displayName,
                    avatarKey: player.avatarKey,
                    remoteApprovedImageUrl: player.remoteApprovedImageUrl,
                    radius: radius,
                    semanticLabel: player.displayName,
                  ),
                ),
                SizedBox(
                  height: veryDense
                      ? 5
                      : dense
                      ? 7
                      : 10 * scale,
                ),
                Text(
                  player.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: veryDense
                        ? 13
                        : dense
                        ? 15
                        : (18 * scale).clamp(16.0, 19.0).toDouble(),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: veryDense ? 2 : 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.diamond_rounded,
                      color: const Color(0xFFB894FF),
                      size: dense ? 12 : 14,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        player.rankLabel ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFC3A8FF),
                          fontSize: dense ? 10 : 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: veryDense ? 2 : 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      color: ready
                          ? const Color(0xFF29D398)
                          : const Color(0xFFFFC94D),
                      size: dense ? 12 : 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      player.rating == null ? '— RP' : '${player.rating} RP',
                      style: TextStyle(
                        color: ready
                            ? const Color(0xFF29D398)
                            : Colors.white.withValues(alpha: .86),
                        fontSize: dense ? 10 : 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Divider(color: accent.withValues(alpha: .28), height: 1),
                SizedBox(
                  height: veryDense
                      ? 5
                      : dense
                      ? 7
                      : 10 * scale,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _FoundStat(
                        value: player.gamesPlayed?.toString() ?? '—',
                        label: 'Matches',
                        dense: dense,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: veryDense ? 23 : 31,
                      color: Colors.white.withValues(alpha: .11),
                    ),
                    Expanded(
                      child: _FoundStat(
                        value: player.winRate == null
                            ? '—'
                            : '${(player.winRate! * 100).round()}%',
                        label: 'Win rate',
                        dense: dense,
                      ),
                    ),
                  ],
                ),
                if (ready && !veryDense) ...[
                  SizedBox(height: dense ? 6 : 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF29D398),
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'READY',
                        style: TextStyle(
                          color: Color(0xFF29D398),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FoundStat extends StatelessWidget {
  const _FoundStat({
    required this.value,
    required this.label,
    required this.dense,
  });

  final String value;
  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: dense ? 12 : 15,
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
            fontSize: dense ? 7 : 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FoundVersusBadge extends StatelessWidget {
  const _FoundVersusBadge({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = (58 * scale).clamp(48.0, 62.0).toDouble();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF263D50), Color(0xFF07131E)],
        ),
        border: Border.all(
          color: const Color(0xFFFFC94D).withValues(alpha: .72),
          width: 1.35,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2FB6FF).withValues(alpha: .15),
            blurRadius: 18,
            offset: const Offset(-7, 0),
          ),
          BoxShadow(
            color: const Color(0xFFFFC94D).withValues(alpha: .15),
            blurRadius: 18,
            offset: const Offset(7, 0),
          ),
        ],
      ),
      child: Text(
        'VS',
        style: TextStyle(
          color: const Color(0xFFFFD66B),
          fontSize: (20 * scale).clamp(17.0, 21.0).toDouble(),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FoundStatusCard extends StatelessWidget {
  const _FoundStatusCard({
    required this.opponentName,
    required this.opponentReady,
    required this.scale,
  });

  final String opponentName;
  final bool opponentReady;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: (66 * scale).clamp(58.0, 72.0).toDouble(),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: (13 * scale).clamp(11.0, 15.0).toDouble(),
        vertical: (10 * scale).clamp(8.0, 12.0).toDouble(),
      ),
      decoration: BoxDecoration(
        color: const Color(0xE00B1A28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF29D398).withValues(alpha: .24),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: (42 * scale).clamp(36.0, 44.0).toDouble(),
            height: (42 * scale).clamp(36.0, 44.0).toDouble(),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF10283A),
              border: Border.all(
                color: const Color(0xFF29D398).withValues(alpha: .35),
              ),
            ),
            child: const Icon(
              Icons.handshake_rounded,
              color: Color(0xFF29D398),
              size: 23,
            ),
          ),
          SizedBox(width: 11 * scale),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Match found',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3 * scale),
                Text(
                  opponentReady
                      ? '$opponentName is ready. Confirm when you are ready.'
                      : '$opponentName matched near your competitive level.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .57),
                    fontSize: (10 * scale).clamp(9.0, 11.0).toDouble(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: Color(0xFF29D398),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
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
    required this.onLeave,
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
  final VoidCallback? onLeave;
  final Widget? floatingControl;

  @override
  Widget build(BuildContext context) {
    final readyCount = (currentReady ? 1 : 0) + (opponentReady ? 1 : 0);
    final bothReady = readyCount == 2;
    final title = bothReady
        ? context.tr('everyone_ready_starting')
        : currentReady
        ? context.tr('waiting_opponent_ready')
        : 'Waiting for both players to confirm';
    final subtitle = bothReady
        ? '2/2 players ready'
        : currentReady
        ? '$readyCount/2 players ready'
        : connectionLabel;

    return Scaffold(
      backgroundColor: const Color(0xFF06111F),
      body: AppBackdrop(
        dim: .28,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final hScale = (width / 390).clamp(.84, 1.10).toDouble();
              final vScale = (height / 800).clamp(.78, 1.06).toDouble();
              final scale = math.min(hScale, vScale).toDouble();
              final side = (16 * hScale).clamp(12.0, 22.0).toDouble();

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, 6, side, 9),
                    child: Column(
                      children: [
                        _ReadyDuelHeader(
                          opponent: opponent,
                          currentPlayer: currentPlayer,
                          opponentReady: opponentReady,
                          currentReady: currentReady,
                          scale: scale,
                        ),
                        SizedBox(height: 10 * scale),
                        Expanded(
                          child: _ReadyVersusArena(
                            currentPlayer: currentPlayer,
                            opponent: opponent,
                            currentReady: currentReady,
                            opponentReady: opponentReady,
                            scale: scale,
                          ),
                        ),
                        SizedBox(height: 10 * scale),
                        _ReadyStatusCard(
                          title: title,
                          subtitle: subtitle,
                          readyCount: readyCount,
                          scale: scale,
                        ),
                        SizedBox(height: 10 * scale),
                        SizedBox(
                          width: double.infinity,
                          height: (60 * scale).clamp(52.0, 66.0).toDouble(),
                          child: FilledButton.icon(
                            onPressed: actionBusy ? null : onAction,
                            icon: actionBusy
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Container(
                                    width: 35,
                                    height: 35,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF29D398),
                                        width: 1.7,
                                      ),
                                    ),
                                    child: Icon(actionIcon, size: 23),
                                  ),
                            label: Text(
                              actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: (17 * scale)
                                    .clamp(15.0, 19.0)
                                    .toDouble(),
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
                                  width: 1.4,
                                ),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        SizedBox(height: 8 * scale),
                        Row(
                          children: [
                            SizedBox(
                              width: 56,
                              height: 56,
                              child: Center(
                                child:
                                    floatingControl ?? const SizedBox.shrink(),
                              ),
                            ),
                            const Spacer(),
                            _ReadyOptionsButton(onLeave: onLeave),
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

class _ReadyOptionsButton extends StatelessWidget {
  const _ReadyOptionsButton({required this.onLeave});

  final VoidCallback? onLeave;

  Future<void> _open(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .46),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Material(
            color: const Color(0xFF101D27),
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'READY ROOM OPTIONS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFFF8C88),
                    ),
                    title: const Text(
                      'Leave ready room',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text('A confirmation is required.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: onLeave == null
                        ? null
                        : () => Navigator.of(sheetContext).pop('leave'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (action == 'leave') onLeave?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton(
        tooltip: 'Ready room options',
        onPressed: () => _open(context),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xD8142430),
          foregroundColor: const Color(0xFFFFC94D),
          side: BorderSide(
            color: const Color(0xFFFFC94D).withValues(alpha: .44),
          ),
        ),
        icon: const Icon(Icons.tune_rounded, size: 24),
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
    required this.scale,
  });

  final MatchmakingVisualPlayer? opponent;
  final MatchmakingVisualPlayer currentPlayer;
  final bool opponentReady;
  final bool currentReady;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: (78 * scale).clamp(68.0, 82.0).toDouble(),
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
              scale: scale,
            ),
          ),
          Container(
            width: (64 * scale).clamp(56.0, 68.0).toDouble(),
            height: (64 * scale).clamp(56.0, 68.0).toDouble(),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF17263A),
              border: Border.all(
                color: const Color(0xFF29D398).withValues(alpha: .72),
                width: 1.8,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(opponentReady ? 1 : 0) + (currentReady ? 1 : 0)}/2',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (20 * scale).clamp(17.0, 22.0).toDouble(),
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
              scale: scale,
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
    required this.scale,
    this.alignEnd = false,
  });

  final MatchmakingVisualPlayer? player;
  final String fallbackName;
  final Color accent;
  final bool ready;
  final bool alignEnd;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final name = p?.displayName.isNotEmpty == true
        ? p!.displayName
        : fallbackName;
    final avatarRadius = (18 * scale).clamp(15.0, 19.0).toDouble();
    final avatar = p == null
        ? Container(
            width: avatarRadius * 2 + 4,
            height: avatarRadius * 2 + 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF122236),
              border: Border.all(color: accent.withValues(alpha: .56)),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: Colors.white54,
            ),
          )
        : Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: ready ? 2 : 1),
            ),
            child: PlayerAvatar(
              displayName: p.displayName,
              avatarKey: p.avatarKey,
              remoteApprovedImageUrl: p.remoteApprovedImageUrl,
              radius: avatarRadius,
              semanticLabel: p.displayName,
            ),
          );
    final info = Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: (12 * scale).clamp(10.0, 13.0).toDouble(),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            p?.rankLabel ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFC3A8FF),
              fontSize: (9 * scale).clamp(8.0, 10.0).toDouble(),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            p?.rating == null ? '— RP' : '${p!.rating} RP',
            style: TextStyle(
              color: ready ? const Color(0xFF29D398) : Colors.white70,
              fontSize: (9 * scale).clamp(8.0, 10.0).toDouble(),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
        children: [avatar, const SizedBox(width: 6), info],
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
    required this.scale,
  });

  final MatchmakingVisualPlayer currentPlayer;
  final MatchmakingVisualPlayer? opponent;
  final bool currentReady;
  final bool opponentReady;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = (constraints.maxWidth * .08).clamp(28.0, 42.0).toDouble();
        final cardWidth = ((constraints.maxWidth - gap) / 2)
            .clamp(118.0, 232.0)
            .toDouble();
        final visualHeight = math
            .min(constraints.maxHeight, 390 * scale)
            .toDouble();

        return Center(
          child: SizedBox(
            width: constraints.maxWidth,
            height: visualHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: cardWidth,
                    height: visualHeight,
                    child: _ReadyPlayerCard(
                      player: opponent,
                      ready: opponentReady,
                      accent: const Color(0xFF3AA9FF),
                      placeholderLabel: context.tr('connecting_players'),
                      scale: scale,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: cardWidth,
                    height: visualHeight,
                    child: _ReadyPlayerCard(
                      player: currentPlayer,
                      ready: currentReady,
                      accent: const Color(0xFFFFC94D),
                      placeholderLabel: context.tr('you'),
                      scale: scale,
                    ),
                  ),
                ),
                Container(
                  width: (60 * scale).clamp(50.0, 64.0).toDouble(),
                  height: (60 * scale).clamp(50.0, 64.0).toDouble(),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF16263A),
                    border: Border.all(
                      color: const Color(0xFFFFC94D).withValues(alpha: .50),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3AA9FF).withValues(alpha: .20),
                        blurRadius: 18,
                        offset: const Offset(-7, 0),
                      ),
                      BoxShadow(
                        color: const Color(0xFFFFC94D).withValues(alpha: .18),
                        blurRadius: 18,
                        offset: const Offset(7, 0),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Color(0xFFFFC94D),
                    size: 31,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReadyPlayerCard extends StatelessWidget {
  const _ReadyPlayerCard({
    required this.player,
    required this.ready,
    required this.accent,
    required this.placeholderLabel,
    required this.scale,
  });

  final MatchmakingVisualPlayer? player;
  final bool ready;
  final Color accent;
  final String placeholderLabel;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 300;
        final radius = dense ? 27.0 : (34 * scale).clamp(30.0, 38.0).toDouble();
        return Container(
          padding: EdgeInsets.fromLTRB(
            (10 * scale).clamp(8.0, 12.0).toDouble(),
            (12 * scale).clamp(9.0, 14.0).toDouble(),
            (10 * scale).clamp(8.0, 12.0).toDouble(),
            (10 * scale).clamp(8.0, 12.0).toDouble(),
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xF0162940), Color(0xF10A1624)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accent.withValues(alpha: .74),
              width: 1.35,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: ready ? .25 : .12),
                blurRadius: ready ? 22 : 16,
              ),
            ],
          ),
          child: p == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: radius * 2.2,
                      height: radius * 2.2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF102139),
                        border: Border.all(
                          color: accent.withValues(alpha: .60),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_search_rounded,
                        color: Colors.white54,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      placeholderLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: accent,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: .24),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: PlayerAvatar(
                        displayName: p.displayName,
                        avatarKey: p.avatarKey,
                        remoteApprovedImageUrl: p.remoteApprovedImageUrl,
                        radius: radius,
                        semanticLabel: p.displayName,
                      ),
                    ),
                    SizedBox(height: dense ? 7 : 10),
                    Text(
                      p.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: dense ? 14 : 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.rankLabel ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFC3A8FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Divider(color: Colors.white.withValues(alpha: .15)),
                    SizedBox(height: dense ? 6 : 8),
                    Row(
                      children: [
                        Expanded(
                          child: _ReadyStat(
                            value: p.gamesPlayed?.toString() ?? '—',
                            label: 'Matches',
                          ),
                        ),
                        Expanded(
                          child: _ReadyStat(
                            value: p.winRate == null
                                ? '—'
                                : '${(p.winRate! * 100).round()}%',
                            label: 'Win rate',
                          ),
                        ),
                        Expanded(
                          child: _ReadyStat(
                            value: p.rating?.toString() ?? '—',
                            label: 'RP',
                            accent: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          ready
                              ? Icons.check_circle_rounded
                              : Icons.link_rounded,
                          color: ready
                              ? const Color(0xFF29D398)
                              : const Color(0xFF66C7FF),
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          ready ? context.tr('ready') : context.tr('connected'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _ReadyStat extends StatelessWidget {
  const _ReadyStat({
    required this.value,
    required this.label,
    this.accent = false,
  });

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
            color: accent ? const Color(0xFFC3A8FF) : Colors.white,
            fontSize: 12,
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
    required this.scale,
  });

  final String title;
  final String subtitle;
  final int readyCount;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (14 * scale).clamp(11.0, 15.0).toDouble(),
        vertical: (11 * scale).clamp(8.0, 12.0).toDouble(),
      ),
      decoration: BoxDecoration(
        color: const Color(0xD9102030),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(
        children: [
          Container(
            width: (42 * scale).clamp(36.0, 44.0).toDouble(),
            height: (42 * scale).clamp(36.0, 44.0).toDouble(),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF122C44),
              border: Border.all(
                color: const Color(0xFF66C7FF).withValues(alpha: .42),
              ),
            ),
            child: const Icon(
              Icons.group_rounded,
              color: Colors.white,
              size: 23,
            ),
          ),
          SizedBox(width: 11 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (13 * scale).clamp(11.0, 14.0).toDouble(),
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
                    fontSize: (10 * scale).clamp(9.0, 11.0).toDouble(),
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
              color: readyCount == 2
                  ? const Color(0xFF29D398)
                  : const Color(0xFFFFC94D),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
