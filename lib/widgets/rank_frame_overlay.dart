import 'package:flutter/material.dart';

import '../models/rank_identity_models.dart';

class RankFrameOverlay extends StatelessWidget {
  const RankFrameOverlay({
    super.key,
    required this.child,
    required this.size,
    this.frameKey,
    this.decorationKeys = const <String>[],
  });

  final Widget child;
  final double size;
  final String? frameKey;
  final List<String> decorationKeys;

  @override
  Widget build(BuildContext context) {
    final key = frameKey;
    if (key == null || key.isEmpty) return child;
    final tier = rankTierForKey(key);
    final visual = _RankFrameVisual.forTier(tier);
    final decorations = decorationKeys.take(3).toList(growable: false);
    final ringWidth = visual.ringWidth.clamp(1.5, size * .09).toDouble();

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: visual.ringColors),
                boxShadow: [
                  if (visual.glowAlpha > 0)
                    BoxShadow(
                      color: visual.accent.withValues(alpha: visual.glowAlpha),
                      blurRadius: visual.glowBlur,
                      spreadRadius: visual.glowSpread,
                    ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(ringWidth),
                child: ClipOval(child: child),
              ),
            ),
          ),
          if (tier.division <= 2)
            ..._winglets(size: size, visual: visual, tier: tier),
          if (tier.division == 1)
            Positioned(
              top: -size * .055,
              left: size * .36,
              right: size * .36,
              child: Icon(
                tier.league == 'master'
                    ? Icons.workspace_premium_rounded
                    : Icons.diamond_rounded,
                size: size * .23,
                color: visual.accent,
              ),
            ),
          Positioned(
            right: -size * .015,
            bottom: -size * .02,
            child: _DivisionMedallion(
              division: tier.division,
              visual: visual,
              size: size * .29,
            ),
          ),
          if (decorations.isNotEmpty)
            Positioned(
              left: -size * .055,
              top: size * .035,
              child: _DecorationPin(
                keyName: decorations[0],
                size: size * .28,
                frameAccent: visual.accent,
              ),
            ),
          if (decorations.length > 1)
            Positioned(
              right: -size * .055,
              top: size * .035,
              child: _DecorationPin(
                keyName: decorations[1],
                size: size * .28,
                frameAccent: visual.accent,
              ),
            ),
          if (decorations.length > 2)
            Positioned(
              left: size * .355,
              bottom: -size * .075,
              child: _DecorationPin(
                keyName: decorations[2],
                size: size * .27,
                frameAccent: visual.accent,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _winglets({
    required double size,
    required _RankFrameVisual visual,
    required RankTierInfo tier,
  }) {
    final count = tier.division == 1 ? 3 : 2;
    final widgets = <Widget>[];
    for (var i = 0; i < count; i++) {
      final top = size * (.27 + (i * .13));
      final width = size * (.13 + (i * .012));
      widgets.addAll([
        Positioned(
          left: -width * .42,
          top: top,
          child: Transform.rotate(
            angle: -.45,
            child: _Winglet(color: visual.accent, width: width),
          ),
        ),
        Positioned(
          right: -width * .42,
          top: top,
          child: Transform.rotate(
            angle: .45,
            child: _Winglet(color: visual.accent, width: width),
          ),
        ),
      ]);
    }
    return widgets;
  }
}

class _Winglet extends StatelessWidget {
  const _Winglet({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * .42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: .95), color.withValues(alpha: .25)],
        ),
        borderRadius: BorderRadius.circular(width),
        border: Border.all(color: Colors.white.withValues(alpha: .28), width: .7),
      ),
    );
  }
}

class _DivisionMedallion extends StatelessWidget {
  const _DivisionMedallion({
    required this.division,
    required this.visual,
    required this.size,
  });

  final int division;
  final _RankFrameVisual visual;
  final double size;

  @override
  Widget build(BuildContext context) {
    final roman = switch (division) { 1 => 'I', 2 => 'II', _ => 'III' };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: visual.dark,
        border: Border.all(color: visual.accent, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .34),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            roman,
            style: TextStyle(
              color: visual.text,
              fontSize: size * .42,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _DecorationPin extends StatelessWidget {
  const _DecorationPin({
    required this.keyName,
    required this.size,
    required this.frameAccent,
  });

  final String keyName;
  final double size;
  final Color frameAccent;

  @override
  Widget build(BuildContext context) {
    final icon = _decorationIcon(keyName);
    final legendary =
        keyName.contains('50') ||
        keyName.contains('1000') ||
        keyName.contains('master') ||
        keyName.contains('legend') ||
        keyName.contains('crystal');
    final epic =
        keyName.contains('25') ||
        keyName.contains('500') ||
        keyName.contains('gold') ||
        keyName.contains('platinum') ||
        keyName.contains('giant');
    final accent = legendary
        ? const Color(0xFFFFD66B)
        : epic
        ? const Color(0xFFB99CFF)
        : frameAccent;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF10181D),
        border: Border.all(color: accent, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .28),
            blurRadius: 5,
          ),
        ],
      ),
      child: Icon(icon, size: size * .58, color: accent),
    );
  }
}

IconData _decorationIcon(String key) {
  if (key.contains('unbeaten') || key.contains('shield')) {
    return Icons.shield_rounded;
  }
  if (key.contains('streak') || key.contains('flame')) {
    return Icons.local_fire_department_rounded;
  }
  if (key.contains('master') || key.contains('crown')) {
    return Icons.workspace_premium_rounded;
  }
  if (key.contains('perfect') || key.contains('star')) {
    return Icons.auto_awesome_rounded;
  }
  if (key.contains('giant')) return Icons.bolt_rounded;
  if (key.contains('veteran') || key.contains('duel')) {
    return Icons.military_tech_rounded;
  }
  if (key.contains('country')) return Icons.public_rounded;
  if (key.contains('podium')) return Icons.emoji_events_rounded;
  if (key.contains('friendly')) return Icons.people_alt_rounded;
  if (key.contains('wins') || key.contains('victory')) {
    return Icons.emoji_events_rounded;
  }
  if (key.contains('crystal') || key.contains('platinum')) {
    return Icons.diamond_rounded;
  }
  return Icons.workspace_premium_rounded;
}

class _RankFrameVisual {
  const _RankFrameVisual({
    required this.accent,
    required this.dark,
    required this.text,
    required this.ringColors,
    required this.ringWidth,
    required this.glowAlpha,
    required this.glowBlur,
    required this.glowSpread,
  });

  final Color accent;
  final Color dark;
  final Color text;
  final List<Color> ringColors;
  final double ringWidth;
  final double glowAlpha;
  final double glowBlur;
  final double glowSpread;

  factory _RankFrameVisual.forTier(RankTierInfo tier) {
    final divisionBoost = 4 - tier.division;
    final base = switch (tier.league) {
      'silver' => const _FramePalette(
        accent: Color(0xFFD8E1E8),
        dark: Color(0xFF273139),
        text: Color(0xFFF7FBFF),
        secondary: Color(0xFF8DA4B5),
      ),
      'gold' => const _FramePalette(
        accent: Color(0xFFFFCC55),
        dark: Color(0xFF382B0D),
        text: Color(0xFFFFF4C9),
        secondary: Color(0xFFB88420),
      ),
      'platinum' => const _FramePalette(
        accent: Color(0xFF83E5FF),
        dark: Color(0xFF102B36),
        text: Color(0xFFE8FBFF),
        secondary: Color(0xFFBDEFFF),
      ),
      'master' => const _FramePalette(
        accent: Color(0xFFD9A5FF),
        dark: Color(0xFF26143A),
        text: Color(0xFFFFF0FF),
        secondary: Color(0xFFFFD36B),
      ),
      _ => const _FramePalette(
        accent: Color(0xFFD58A55),
        dark: Color(0xFF342016),
        text: Color(0xFFFFE9D7),
        secondary: Color(0xFF8E5533),
      ),
    };
    final colors = <Color>[
      base.secondary,
      base.accent,
      if (divisionBoost >= 2) Colors.white.withValues(alpha: .9),
      base.accent,
      base.secondary,
    ];
    return _RankFrameVisual(
      accent: base.accent,
      dark: base.dark,
      text: base.text,
      ringColors: colors,
      ringWidth: 2.0 + divisionBoost,
      glowAlpha: tier.league == 'master'
          ? .42
          : tier.league == 'platinum'
          ? .30
          : divisionBoost >= 2
          ? .20
          : .10,
      glowBlur: 5.0 + (divisionBoost * 2),
      glowSpread: tier.league == 'master' ? 1.5 : .5,
    );
  }
}

class _FramePalette {
  const _FramePalette({
    required this.accent,
    required this.dark,
    required this.text,
    required this.secondary,
  });

  final Color accent;
  final Color dark;
  final Color text;
  final Color secondary;
}
