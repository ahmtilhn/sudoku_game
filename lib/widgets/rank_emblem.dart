import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/rank_identity_models.dart';

/// Background-free competitive rank emblem.
///
/// Every league has its own metallic palette while III / II / I progressively
/// add chevrons, wings and crown detail. The center 3x3 lattice keeps the art
/// tied to Sudoku instead of using unrelated fantasy imagery.
class RankEmblem extends StatelessWidget {
  const RankEmblem({
    super.key,
    required this.rankKey,
    this.size = 64,
    this.semanticLabel,
  });

  final String rankKey;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tier = rankTierForKey(rankKey);
    final palette = _EmblemPalette.forLeague(tier.league);
    final roman = switch (tier.division) {
      1 => 'I',
      2 => 'II',
      _ => 'III',
    };
    return Semantics(
      image: true,
      label: semanticLabel ?? '${tier.label} rank emblem',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RankEmblemPainter(
                  tier: tier,
                  palette: palette,
                ),
              ),
            ),
            Positioned(
              bottom: size * .075,
              child: Container(
                constraints: BoxConstraints(minWidth: size * .28),
                padding: EdgeInsets.symmetric(
                  horizontal: size * .055,
                  vertical: size * .022,
                ),
                decoration: BoxDecoration(
                  color: palette.deep.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(size),
                  border: Border.all(
                    color: palette.highlight.withValues(alpha: .92),
                    width: math.max(1, size * .018),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: .25),
                      blurRadius: size * .08,
                    ),
                  ],
                ),
                child: Text(
                  roman,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: size * .13,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.4,
                  ),
                ),
              ),
            ),
            if (tier.division == 1)
              Positioned(
                top: -size * .015,
                child: Icon(
                  tier.league == 'master'
                      ? Icons.workspace_premium_rounded
                      : Icons.diamond_rounded,
                  size: size * .23,
                  color: palette.highlight,
                  shadows: [
                    Shadow(
                      color: palette.accent.withValues(alpha: .45),
                      blurRadius: size * .08,
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

class _RankEmblemPainter extends CustomPainter {
  const _RankEmblemPainter({required this.tier, required this.palette});

  final RankTierInfo tier;
  final _EmblemPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h * .47);

    _drawWings(canvas, size);

    final shield = Path()
      ..moveTo(w * .29, h * .22)
      ..quadraticBezierTo(w * .50, h * .12, w * .71, h * .22)
      ..lineTo(w * .68, h * .60)
      ..quadraticBezierTo(w * .62, h * .76, w * .50, h * .84)
      ..quadraticBezierTo(w * .38, h * .76, w * .32, h * .60)
      ..close();

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: .28)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * .045);
    canvas.save();
    canvas.translate(0, h * .025);
    canvas.drawPath(shield, shadowPaint);
    canvas.restore();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          palette.highlight,
          palette.accent,
          palette.deep,
          palette.accent,
        ],
        stops: const [0, .30, .70, 1],
      ).createShader(Offset.zero & size);
    canvas.drawPath(shield, fill);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * .025)
      ..color = palette.text.withValues(alpha: .72);
    canvas.drawPath(shield, border);

    final inner = Path()
      ..moveTo(w * .36, h * .29)
      ..quadraticBezierTo(w * .50, h * .23, w * .64, h * .29)
      ..lineTo(w * .62, h * .56)
      ..quadraticBezierTo(w * .58, h * .68, w * .50, h * .73)
      ..quadraticBezierTo(w * .42, h * .68, w * .38, h * .56)
      ..close();
    canvas.drawPath(
      inner,
      Paint()..color = palette.deep.withValues(alpha: .76),
    );

    _drawSudokuGrid(canvas, center, w * .22);
    _drawDivisionMarks(canvas, size);
  }

  void _drawWings(Canvas canvas, Size size) {
    final count = switch (tier.division) {
      1 => 3,
      2 => 2,
      _ => 1,
    };
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2, size.width * .055)
      ..color = palette.accent.withValues(alpha: .92);
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1, size.width * .018)
      ..color = palette.highlight.withValues(alpha: .82);

    for (var index = 0; index < count; index++) {
      final y = size.height * (.34 + index * .105);
      final reach = size.width * (.10 + index * .025);
      final leftA = Offset(size.width * .29, y);
      final leftB = Offset(size.width * .12 - reach * .15, y - reach);
      final rightA = Offset(size.width * .71, y);
      final rightB = Offset(size.width * .88 + reach * .15, y - reach);
      canvas.drawLine(leftA, leftB, paint);
      canvas.drawLine(rightA, rightB, paint);
      canvas.drawLine(leftA, leftB, highlight);
      canvas.drawLine(rightA, rightB, highlight);
    }
  }

  void _drawSudokuGrid(Canvas canvas, Offset center, double extent) {
    final rect = Rect.fromCenter(
      center: center,
      width: extent,
      height: extent,
    );
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, extent * .055)
      ..color = palette.text.withValues(alpha: .90);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(extent * .08)),
      outer,
    );
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.7, extent * .025)
      ..color = palette.text.withValues(alpha: .70);
    for (var index = 1; index < 3; index++) {
      final fraction = index / 3;
      final x = rect.left + rect.width * fraction;
      final y = rect.top + rect.height * fraction;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), thin);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), thin);
    }
    final dot = Paint()..color = palette.highlight;
    canvas.drawCircle(center, extent * .055, dot);
  }

  void _drawDivisionMarks(Canvas canvas, Size size) {
    final count = switch (tier.division) {
      1 => 3,
      2 => 2,
      _ => 1,
    };
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.4, size.width * .025)
      ..color = palette.highlight.withValues(alpha: .94);
    for (var index = 0; index < count; index++) {
      final y = size.height * (.61 + index * .045);
      canvas.drawLine(
        Offset(size.width * .44, y),
        Offset(size.width * .50, y + size.height * .025),
        paint,
      );
      canvas.drawLine(
        Offset(size.width * .50, y + size.height * .025),
        Offset(size.width * .56, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RankEmblemPainter oldDelegate) {
    return oldDelegate.tier.key != tier.key;
  }
}

class _EmblemPalette {
  const _EmblemPalette({
    required this.accent,
    required this.highlight,
    required this.deep,
    required this.text,
  });

  final Color accent;
  final Color highlight;
  final Color deep;
  final Color text;

  factory _EmblemPalette.forLeague(String league) {
    return switch (league) {
      'silver' => const _EmblemPalette(
          accent: Color(0xFFAABBC7),
          highlight: Color(0xFFF2F7FA),
          deep: Color(0xFF3B4A54),
          text: Color(0xFFFFFFFF),
        ),
      'gold' => const _EmblemPalette(
          accent: Color(0xFFD7A631),
          highlight: Color(0xFFFFE69A),
          deep: Color(0xFF5B400C),
          text: Color(0xFFFFF4C9),
        ),
      'platinum' => const _EmblemPalette(
          accent: Color(0xFF53CDE8),
          highlight: Color(0xFFD5F8FF),
          deep: Color(0xFF123946),
          text: Color(0xFFE8FBFF),
        ),
      'master' => const _EmblemPalette(
          accent: Color(0xFFB77BE4),
          highlight: Color(0xFFFFD66B),
          deep: Color(0xFF311448),
          text: Color(0xFFFFF4FF),
        ),
      _ => const _EmblemPalette(
          accent: Color(0xFFB96E3D),
          highlight: Color(0xFFFFC39A),
          deep: Color(0xFF492516),
          text: Color(0xFFFFE5D1),
        ),
    };
  }
}
