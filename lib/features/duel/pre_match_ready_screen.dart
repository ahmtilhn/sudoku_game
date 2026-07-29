import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../services/online_duel_controller.dart';
import '../../services/online_duel_models.dart';
import '../../services/online_duel_transport.dart';
import '../../widgets/player_avatar.dart';
import 'online_duel_screen.dart';

class PreMatchReadyScreen extends StatefulWidget {
  const PreMatchReadyScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<PreMatchReadyScreen> createState() => _PreMatchReadyScreenState();
}

class _PreMatchReadyScreenState extends State<PreMatchReadyScreen> {
  static const Duration _minimumSearchStage = Duration(milliseconds: 2600);

  OnlineDuelController? _controller;
  StreamSubscription<OnlineDuelSnapshot>? _subscription;
  OnlineDuelSnapshot? _snapshot;
  Object? _error;
  bool _minimumElapsed = false;
  bool _screenLoadedSent = false;
  bool _handedOff = false;
  Timer? _minimumTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _minimumTimer = Timer(_minimumSearchStage, () {
      if (!mounted) return;
      setState(() => _minimumElapsed = true);
      _sendScreenLoaded();
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
        });
        _sendScreenLoaded();
        if (snapshot.status == OnlineDuelStatus.active) {
          _openGame(controller);
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
    _controller?.ready();
  }

  void _openGame(OnlineDuelController controller) {
    if (_handedOff || !_minimumElapsed) return;
    _handedOff = true;
    Navigator.of(context).pushReplacement(
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
    return Scaffold(
      backgroundColor: const Color(0xFF061124),
      body: SafeArea(
        child: Stack(
          children: [
            const _ArenaBackground(),
            Positioned(
              left: 12,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: context.tr('cancel_search'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
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
                      color: Colors.white.withValues(alpha: .62),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 560;
                        return Stack(
                          children: [
                            Align(
                              alignment: const Alignment(-.78, -.84),
                              child: _PlayerReadyCard(
                                player: _you,
                                fallbackName: context.tr('you'),
                                ready: _you?.ready == true,
                                highlighted: true,
                                unknown: false,
                                compact: compact,
                              ),
                            ),
                            Align(
                              alignment: const Alignment(.74, .28),
                              child: _PlayerReadyCard(
                                player: _opponent,
                                fallbackName: readyStage
                                    ? context.tr('opponent')
                                    : context.tr('searching_opponent_short'),
                                ready: _opponent?.ready == true,
                                highlighted: false,
                                unknown: _opponent == null,
                                compact: compact,
                              ),
                            ),
                            Center(
                              child: _CenterBadge(
                                readyStage: readyStage,
                                bothReady:
                                    _you?.ready == true &&
                                    _opponent?.ready == true,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_error != null) ...[
                    _StatusBar(
                      icon: Icons.cloud_off_outlined,
                      text: context.tr('online_connection_failed', <Object>[
                        _error!,
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ] else ...[
                    _StatusBar(
                      icon: readyStage
                          ? Icons.hourglass_top_rounded
                          : Icons.shield_outlined,
                      text: readyStage
                          ? (_you?.ready == true
                                ? context.tr('waiting_opponent_ready')
                                : context.tr('match_ready_prompt'))
                          : context.tr('elo_hint'),
                      trailing: readyStage ? '$_secondsRemaining' : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (readyStage)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _you?.ready == true ? null : _ready,
                        icon: Icon(
                          _you?.ready == true
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          _you?.ready == true
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
}

class _ArenaBackground extends StatelessWidget {
  const _ArenaBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArenaPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _ArenaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF061124), Color(0xFF081A36), Color(0xFF120D32)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF58A8FF).withValues(alpha: .85),
          const Color(0xFFB64DFF).withValues(alpha: .55),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..strokeWidth = 1.6;
    canvas.drawLine(
      Offset(size.width * .68, size.height * .16),
      Offset(size.width * .38, size.height * .78),
      line,
    );

    final glow = Paint()
      ..color = const Color(0xFF58A8FF).withValues(alpha: .08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(Offset(size.width * .5, size.height * .52), 86, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
        ? const Color(0xFF2E7BFF)
        : const Color(0xFF9B4DFF);
    final name = player?.displayName ?? fallbackName;
    final radius = compact ? 30.0 : 36.0;
    return Container(
      width: compact ? 126 : 142,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1B36).withValues(alpha: .86),
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
              const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFFFC547),
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
                  const Icon(
                    Icons.check_circle_outline,
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
  const _CenterBadge({required this.readyStage, required this.bothReady});

  final bool readyStage;
  final bool bothReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF13274E),
        border: Border.all(color: const Color(0xFF9B4DFF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9B4DFF).withValues(alpha: .35),
            blurRadius: 24,
          ),
        ],
      ),
      child: Icon(
        readyStage
            ? (bothReady ? Icons.handshake : Icons.how_to_reg)
            : Icons.search,
        color: Colors.white,
        size: 30,
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.icon, required this.text, this.trailing});

  final IconData icon;
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF172344).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8B63FF)),
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
                border: Border.all(color: const Color(0xFF8B63FF)),
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
