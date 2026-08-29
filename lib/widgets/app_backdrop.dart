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
    final duelSnapshot = OnlineDuelController.activeSnapshot;
    final showReadyCountdown =
        duelSnapshot?.status == OnlineDuelStatus.readyWindow &&
        duelSnapshot?.readyDeadline != null;
    final showStartingFlash =
        duelSnapshot?.status == OnlineDuelStatus.active &&
        duelSnapshot?.turnNumber == 1 &&
        duelSnapshot?.scores.values.every((value) => value == 0) == true &&
        duelSnapshot?.correctMoves.values.every((value) => value == 0) == true &&
        duelSnapshot?.mistakes.values.every((value) => value == 0) == true;

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
        if (showReadyCountdown || showStartingFlash)
          OnlineReadyCountdownOverlay(
            snapshot: duelSnapshot!,
            showStartingFlash: showStartingFlash,
          ),
      ],
    );
    return RepaintBoundary(child: content);
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
