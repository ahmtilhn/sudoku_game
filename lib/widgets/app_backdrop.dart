import 'dart:async';

import 'package:flutter/material.dart';

import '../features/duel/online_ready_countdown_overlay.dart';
import '../services/online_duel_controller.dart';
import '../services/online_duel_models.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, this.child, this.animation, this.dim = .18});

  static const String assetPath = 'assets/images/app_backdrop.png';

  final Widget? child;
  final Animation<double>? animation;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          assetPath,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) =>
              const _FallbackBackdrop(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: dim),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .08),
                Colors.transparent,
                Colors.black.withValues(alpha: .22),
              ],
            ),
          ),
        ),
        if (animation != null)
          AnimatedBuilder(
            animation: animation!,
            builder: (context, _) =>
                CustomPaint(painter: _BackdropMotionPainter(animation!.value)),
          ),
        ?child,
        const _DuelCountdownLayer(),
      ],
    );
    return RepaintBoundary(child: content);
  }
}

/// Keeps the duel countdown reactive without forcing the whole backdrop to
/// repaint. `OnlineDuelController.activeSnapshot` is intentionally a cheap
/// synchronous getter, so this lightweight watcher bridges it into the widget
/// tree. Once the ready window appears, the countdown overlay owns its own
/// 100 ms ticker for smooth 3-2-1 transitions.
class _DuelCountdownLayer extends StatefulWidget {
  const _DuelCountdownLayer();

  @override
  State<_DuelCountdownLayer> createState() => _DuelCountdownLayerState();
}

class _DuelCountdownLayerState extends State<_DuelCountdownLayer> {
  Timer? _snapshotWatcher;
  OnlineDuelSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = OnlineDuelController.activeSnapshot;
    _snapshotWatcher = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _syncSnapshot(),
    );
  }

  @override
  void dispose() {
    _snapshotWatcher?.cancel();
    super.dispose();
  }

  void _syncSnapshot() {
    if (!mounted) return;
    final next = OnlineDuelController.activeSnapshot;
    if (identical(next, _snapshot)) return;
    setState(() => _snapshot = next);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) return const SizedBox.shrink();

    final showReadyCountdown =
        snapshot.status == OnlineDuelStatus.readyWindow &&
        snapshot.readyDeadline != null;
    final showStartingFlash =
        snapshot.status == OnlineDuelStatus.active &&
        snapshot.turnNumber == 1 &&
        snapshot.scores.values.every((value) => value == 0) &&
        snapshot.correctMoves.values.every((value) => value == 0) &&
        snapshot.mistakes.values.every((value) => value == 0);

    if (!showReadyCountdown && !showStartingFlash) {
      return const SizedBox.shrink();
    }

    return OnlineReadyCountdownOverlay(
      snapshot: snapshot,
      showStartingFlash: showStartingFlash,
    );
  }
}

class _BackdropMotionPainter extends CustomPainter {
  const _BackdropMotionPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final start = Offset(size.width * .62, size.height * -.06);
    final end = Offset(size.width * .38, size.height * 1.06);
    final line = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFFFFC94D).withValues(alpha: .12),
          Colors.white.withValues(alpha: .10),
          const Color(0xFF29D398).withValues(alpha: .10),
          Colors.transparent,
        ],
      ).createShader(rect)
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final t = Curves.easeInOutSine.transform(progress % 1);
    final a = Offset.lerp(start, end, (t - .10).clamp(0, 1))!;
    final b = Offset.lerp(start, end, (t + .10).clamp(0, 1))!;
    canvas.drawLine(a, b, line);
  }

  @override
  bool shouldRepaint(covariant _BackdropMotionPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _FallbackBackdrop extends StatelessWidget {
  const _FallbackBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1215), Color(0xFF121B20), Color(0xFF121B20)],
        ),
      ),
    );
  }
}
