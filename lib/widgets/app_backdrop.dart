import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
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
          _OnlineReadyTransitionOverlay(
            snapshot: duelSnapshot!,
            showStartingFlash: showStartingFlash,
          ),
      ],
    );
    return RepaintBoundary(child: content);
  }
}

class _OnlineReadyTransitionOverlay extends StatefulWidget {
  const _OnlineReadyTransitionOverlay({
    required this.snapshot,
    required this.showStartingFlash,
  });

  final OnlineDuelSnapshot snapshot;
  final bool showStartingFlash;

  @override
  State<_OnlineReadyTransitionOverlay> createState() =>
      _OnlineReadyTransitionOverlayState();
}

class _OnlineReadyTransitionOverlayState
    extends State<_OnlineReadyTransitionOverlay> {
  Timer? _ticker;
  Timer? _startingFlashTimer;
  Duration _serverClockOffset = Duration.zero;
  bool _startingFlashVisible = true;

  @override
  void initState() {
    super.initState();
    _syncServerClock();
    _syncTimers();
  }

  @override
  void didUpdateWidget(covariant _OnlineReadyTransitionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.serverTime != widget.snapshot.serverTime ||
        oldWidget.snapshot.revision != widget.snapshot.revision) {
      _syncServerClock();
    }
    if (!oldWidget.showStartingFlash && widget.showStartingFlash) {
      _startingFlashVisible = true;
    }
    _syncTimers();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _startingFlashTimer?.cancel();
    super.dispose();
  }

  void _syncServerClock() {
    _serverClockOffset = widget.snapshot.serverTime.difference(DateTime.now());
  }

  void _syncTimers() {
    final counting =
        widget.snapshot.status == OnlineDuelStatus.readyWindow &&
        widget.snapshot.readyDeadline != null;
    if (counting) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }

    if (widget.showStartingFlash && _startingFlashVisible) {
      _startingFlashTimer ??= Timer(const Duration(milliseconds: 650), () {
        _startingFlashTimer = null;
        if (mounted) setState(() => _startingFlashVisible = false);
      });
    } else if (!widget.showStartingFlash) {
      _startingFlashTimer?.cancel();
      _startingFlashTimer = null;
    }
  }

  int _remainingSeconds() {
    final deadline = widget.snapshot.readyDeadline;
    if (deadline == null) return 0;
    final serverNow = DateTime.now().add(_serverClockOffset);
    final remainingMs = deadline.difference(serverNow).inMilliseconds;
    if (remainingMs <= 0) return 0;
    return ((remainingMs + 999) ~/ 1000).clamp(0, 10).toInt();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showStartingFlash) {
      if (!_startingFlashVisible) return const SizedBox.shrink();
      return const IgnorePointer(
        child: Center(child: _MatchStartingCard()),
      );
    }

    final seconds = _remainingSeconds();
    final lastThree = seconds > 0 && seconds <= 3;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (lastThree)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .26),
              ),
            ),
          if (seconds >= 4)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 58,
              left: 16,
              right: 16,
              child: Center(child: _SmallReadyCountdown(seconds: seconds)),
            )
          else if (lastThree)
            Center(child: _LargeReadyCountdown(seconds: seconds))
          else
            const Center(child: _MatchStartingCard()),
        ],
      ),
    );
  }
}

class _SmallReadyCountdown extends StatelessWidget {
  const _SmallReadyCountdown({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: context.tr('automatic_start_seconds', <Object>[seconds]),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xE60A1722),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFF29D398).withValues(alpha: .42),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timer_outlined,
              color: Color(0xFF29D398),
              size: 16,
            ),
            const SizedBox(width: 7),
            Text(
              context.tr('automatic_start_seconds', <Object>[seconds]),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: .15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LargeReadyCountdown extends StatelessWidget {
  const _LargeReadyCountdown({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '$seconds',
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(seconds),
        tween: Tween<double>(begin: .62, end: 1),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          child: Opacity(opacity: scale, child: child),
        ),
        child: Container(
          width: 142,
          height: 142,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF173746), Color(0xF20A1722)],
            ),
            border: Border.all(color: const Color(0xFFFFC94D), width: 2.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFC94D).withValues(alpha: .24),
                blurRadius: 34,
                spreadRadius: 3,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .42),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Text(
            '$seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 82,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -3,
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchStartingCard extends StatelessWidget {
  const _MatchStartingCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: context.tr('everyone_ready_starting'),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: .92, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          child: Opacity(opacity: scale, child: child),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          decoration: BoxDecoration(
            color: const Color(0xF20A1722),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF29D398).withValues(alpha: .68),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF29D398).withValues(alpha: .16),
                blurRadius: 24,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .36),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                color: Color(0xFF29D398),
                size: 24,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr('everyone_ready_starting'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
