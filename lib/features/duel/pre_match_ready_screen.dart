import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/duel_asset_icon.dart';
import '../../widgets/player_avatar.dart';
import 'online_duel_screen.dart';

class PreMatchReadyScreen extends StatefulWidget {
  const PreMatchReadyScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<PreMatchReadyScreen> createState() => _PreMatchReadyScreenState();
}

class _PreMatchReadyScreenState extends State<PreMatchReadyScreen>
    with TickerProviderStateMixin {
  static const Duration _minimumSearchStage = Duration(milliseconds: 2600);

  OnlineDuelController? _controller;
  StreamSubscription<OnlineDuelSnapshot>? _subscription;
  OnlineDuelSnapshot? _snapshot;
  Object? _error;
  bool _minimumElapsed = false;
  bool _screenLoadedSent = false;
  bool _handedOff = false;
  bool _localReadyPressed = false;
  bool _openingMatch = false;
  Timer? _minimumTimer;
  Timer? _clockTimer;
  late final AnimationController _pulseController;
  late final AnimationController _exitController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _minimumTimer = Timer(_minimumSearchStage, () {
      if (!mounted) return;
      setState(() => _minimumElapsed = true);
      _sendScreenLoaded();
      final controller = _controller;
      if (controller != null && _snapshot?.status == OnlineDuelStatus.active) {
        unawaited(_openGame(controller));
      }
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_connect());
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    _clockTimer?.cancel();
    _pulseController.dispose();
    _exitController.dispose();
    unawaited(_subscription?.cancel());
    if (!_handedOff) {
      unawaited(_controller?.dispose());
    }
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final controller = OnlineDuelController(
        await WebSocketOnlineDuelTransport.connect(widget.roomId),
      )..start();
      final subscription = controller.snapshots.listen((snapshot) {
        if (!mounted) return;
        setState(() {
          _controller = controller;
          _snapshot = snapshot;
          _error = null;
          if (snapshot.players[snapshot.youSeat]?.ready == true) {
            _localReadyPressed = true;
          }
        });
        _sendScreenLoaded();
        if (snapshot.status == OnlineDuelStatus.active) {
          unawaited(_openGame(controller));
        }
      });
      setState(() {
        _controller = controller;
        _subscription = subscription;
      });
      controller.requestSnapshot();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _sendScreenLoaded() {
    if (!_minimumElapsed || _screenLoadedSent || _snapshot == null) return;
    _screenLoadedSent = true;
    _controller?.screenLoaded();
  }

  void _ready() {
    final you = _you;
    if (you == null || you.ready) return;
    setState(() => _localReadyPressed = true);
    _controller?.ready();
  }

  Future<void> _openGame(OnlineDuelController controller) async {
    if (_handedOff || !_minimumElapsed) return;
    _handedOff = true;
    setState(() => _openingMatch = true);
    await _exitController.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 680),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) =>
            OnlineDuelScreen(roomId: widget.roomId, controller: controller),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return ScaleTransition(
            scale: Tween<double>(begin: .86, end: 1).animate(curved),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(.12, 1, curve: Curves.easeOut),
              ),
              child: child,
            ),
          );
        },
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

  int get _secondsRemaining {
    final deadline = _snapshot?.readyDeadline;
    if (deadline == null) return 5;
    final diff = deadline.difference(DateTime.now()).inSeconds;
    return diff.clamp(0, 99);
  }

  @override
  Widget build(BuildContext context) {
    final readyStage =
        _minimumElapsed &&
        (_snapshot?.status == OnlineDuelStatus.readyWindow ||
            _snapshot?.status == OnlineDuelStatus.waiting);
    final youReady = _you?.ready == true || _localReadyPressed;
    final opponentReady = _opponent?.ready == true;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1215),
      body: SafeArea(
        child: Stack(
          children: [
            AppBackdrop(animation: _pulseController),
            Positioned(
              left: 12,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: context.tr('cancel_search'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const DuelAssetIcon(DuelAsset.back, size: 22),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 16),
              child: Column(
                children: [
                  Text(
                    readyStage
                        ? context.tr('ready_question')
                        : context.tr('finding_opponent_title'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    readyStage
                        ? context.tr('ready_when_opponent_ready')
                        : context.tr('searching_similar_opponents'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .74),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 560;
                        final cardWidth = compact ? 126.0 : 142.0;
                        final gap = constraints.maxWidth < 390 ? 46.0 : 62.0;
                        final side = math.max(
                          0.0,
                          (constraints.maxWidth - (cardWidth * 2) - gap) / 2,
                        );
                        final top = compact ? 18.0 : 28.0;
                        final bottom = top;
                        return Stack(
                          children: [
                            AnimatedBuilder(
                              animation: _exitController,
                              builder: (context, child) {
                                final value = Curves.easeInOutCubic.transform(
                                  _exitController.value,
                                );
                                return Positioned(
                                  left:
                                      side -
                                      (constraints.maxWidth * .52 * value),
                                  top: top,
                                  width: cardWidth,
                                  child: Opacity(
                                    opacity: 1 - (.55 * value),
                                    child: child,
                                  ),
                                );
                              },
                              child: _PlayerReadyCard(
                                player: _you,
                                fallbackName: context.tr('you'),
                                ready: youReady,
                                highlighted: true,
                                unknown: false,
                                compact: compact,
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _exitController,
                              builder: (context, child) {
                                final value = Curves.easeInOutCubic.transform(
                                  _exitController.value,
                                );
                                return Positioned(
                                  right:
                                      side -
                                      (constraints.maxWidth * .52 * value),
                                  bottom: bottom,
                                  width: cardWidth,
                                  child: Opacity(
                                    opacity: 1 - (.55 * value),
                                    child: child,
                                  ),
                                );
                              },
                              child: _PlayerReadyCard(
                                player: _opponent,
                                fallbackName: readyStage
                                    ? context.tr('opponent')
                                    : context.tr('searching_opponent_short'),
                                ready: opponentReady,
                                highlighted: false,
                                unknown: _opponent == null,
                                compact: compact,
                              ),
                            ),
                            Center(
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 1, end: 1.28)
                                    .animate(
                                      CurvedAnimation(
                                        parent: _exitController,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                child: FadeTransition(
                                  opacity: Tween<double>(begin: 1, end: 0)
                                      .animate(
                                        CurvedAnimation(
                                          parent: _exitController,
                                          curve: Curves.easeIn,
                                        ),
                                      ),
                                  child: _CenterBadge(
                                    readyStage: readyStage,
                                    bothReady: youReady && opponentReady,
                                    animation: _pulseController,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_error != null) ...[
                    _StatusBar(
                      asset: DuelAsset.cloud,
                      text: context.tr('online_connection_failed', <Object>[
                        _error!,
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ] else ...[
                    _StatusBar(
                      asset: readyStage ? DuelAsset.timer : DuelAsset.shield,
                      text: readyStage
                          ? _readyStatusText(context, youReady, opponentReady)
                          : context.tr('elo_hint'),
                      trailing: readyStage ? '$_secondsRemaining' : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (readyStage)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: youReady || _openingMatch ? null : _ready,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF29D398),
                          foregroundColor: const Color(0xFF08110E),
                        ),
                        icon: DuelAssetIcon(
                          youReady ? DuelAsset.check : DuelAsset.shield,
                          size: 22,
                        ),
                        label: Text(
                          youReady
                              ? context.tr('ready')
                              : context.tr('i_am_ready'),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.tr('cancel_search')),
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

  String _readyStatusText(
    BuildContext context,
    bool youReady,
    bool opponentReady,
  ) {
    if (youReady && opponentReady) return context.tr('everyone_ready_starting');
    if (youReady) return context.tr('you_ready_waiting_opponent');
    if (opponentReady) return context.tr('opponent_ready_waiting_you');
    return context.tr('match_ready_prompt');
  }
}

class _PlayerReadyCard extends StatelessWidget {
  const _PlayerReadyCard({
    required this.player,
    required this.fallbackName,
    required this.ready,
    required this.highlighted,
    required this.unknown,
    required this.compact,
  });

  final OnlineDuelPlayer? player;
  final String fallbackName;
  final bool ready;
  final bool highlighted;
  final bool unknown;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final borderColor = highlighted
        ? const Color(0xFF29D398)
        : const Color(0xFF7A5CFF);
    final name = player?.displayName ?? fallbackName;
    final radius = compact ? 30.0 : 36.0;
    return Container(
      width: compact ? 126 : 142,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFF18242B).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: .75)),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: .22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerAvatar(
            displayName: name,
            avatarKey: player?.avatarKey ?? 'matchmaking-$name',
            radius: radius,
            semanticLabel: context.tr('player_avatar_semantics', <Object>[
              name,
            ]),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unknown ? context.tr('world') : context.tr('elo_unknown'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: .58),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DuelAssetIcon(
                DuelAsset.trophy,
                color: Color(0xFFFFC94D),
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                unknown ? '?' : '1000',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'ELO',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .48),
              fontSize: 11,
            ),
          ),
          if (ready) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0E8E60).withValues(alpha: .65),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const DuelAssetIcon(
                    DuelAsset.check,
                    color: Color(0xFF46F5A8),
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    context.tr('ready').toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF46F5A8),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CenterBadge extends StatelessWidget {
  const _CenterBadge({
    required this.readyStage,
    required this.bothReady,
    required this.animation,
  });

  final bool readyStage;
  final bool bothReady;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final pulse = Curves.easeOut.transform(animation.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 58 + (pulse * 42),
              height: 58 + (pulse * 42),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(
                    0xFF29D398,
                  ).withValues(alpha: .42 * (1 - pulse)),
                ),
              ),
            ),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF22313A),
                border: Border.all(color: const Color(0xFF29D398), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF29D398).withValues(alpha: .30),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: DuelAssetIcon(
                readyStage
                    ? (bothReady ? DuelAsset.people : DuelAsset.check)
                    : DuelAsset.search,
                color: Colors.white,
                size: 30,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.asset, required this.text, this.trailing});

  final String asset;
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF18242B).withValues(alpha: .90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          DuelAssetIcon(asset, color: const Color(0xFF29D398), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white.withValues(alpha: .72)),
            ),
          ),
          if (trailing != null)
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF29D398)),
              ),
              child: Text(
                trailing!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
