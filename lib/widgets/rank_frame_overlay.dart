import 'package:flutter/material.dart';

import '../models/rank_frame_asset_catalog.dart';
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

    final normalizedKey = RankFrameAssetCatalog.normalizeKey(key);
    final tier = rankTierForKey(normalizedKey);
    final frameAccent = _frameAccentForLeague(tier.league);
    final decorations = decorationKeys.take(3).toList(growable: false);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodedSize = (size * pixelRatio * 1.15)
        .round()
        .clamp(64, 512)
        .toInt();

    // The PNGs include the decorative outer frame. A very small inset keeps
    // the circular avatar safely inside that artwork without shrinking it
    // noticeably on compact leaderboard rows.
    final avatarInset = size * .055;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(avatarInset),
              child: child,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset(
                RankFrameAssetCatalog.assetPathForKey(normalizedKey),
                fit: BoxFit.contain,
                cacheWidth: decodedSize,
                cacheHeight: decodedSize,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                // `assets/frames/` remains the only frame source. If an asset
                // is accidentally missing we keep the avatar usable rather
                // than drawing a second, unrelated synthetic frame.
                errorBuilder: (_, _, _) => const SizedBox.expand(),
              ),
            ),
          ),
          if (decorations.isNotEmpty)
            Positioned(
              left: -size * .055,
              top: size * .035,
              child: _DecorationPin(
                keyName: decorations[0],
                size: size * .28,
                frameAccent: frameAccent,
              ),
            ),
          if (decorations.length > 1)
            Positioned(
              right: -size * .055,
              top: size * .035,
              child: _DecorationPin(
                keyName: decorations[1],
                size: size * .28,
                frameAccent: frameAccent,
              ),
            ),
          if (decorations.length > 2)
            Positioned(
              left: size * .355,
              bottom: -size * .075,
              child: _DecorationPin(
                keyName: decorations[2],
                size: size * .27,
                frameAccent: frameAccent,
              ),
            ),
        ],
      ),
    );
  }
}

Color _frameAccentForLeague(String league) {
  return switch (league) {
    'silver' => const Color(0xFFD8E1E8),
    'gold' => const Color(0xFFFFCC55),
    'platinum' => const Color(0xFF83E5FF),
    'master' => const Color(0xFFD9A5FF),
    _ => const Color(0xFFD58A55),
  };
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
