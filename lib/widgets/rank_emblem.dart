import 'package:flutter/material.dart';

import '../models/rank_identity_models.dart';

/// Official competitive rank artwork shipped with the app.
///
/// Keep this map as the single UI source of truth for rank imagery. Rank keys
/// use the domain spelling `platinum`, while the current asset filenames use
/// `platinium`; the mismatch is intentionally handled here so the rest of the
/// app never needs to know about it.
const Map<String, String> rankEmblemAssets = <String, String>{
  'bronze_3': 'assets/rank/bronze_3.png',
  'bronze_2': 'assets/rank/bronze_2.png',
  'bronze_1': 'assets/rank/bronze_1.png',
  'silver_3': 'assets/rank/silver_3.png',
  'silver_2': 'assets/rank/silver_2.png',
  'silver_1': 'assets/rank/silver_1.png',
  'gold_3': 'assets/rank/gold_3.png',
  'gold_2': 'assets/rank/gold_2.png',
  'gold_1': 'assets/rank/gold_1.png',
  'platinum_3': 'assets/rank/platinium_3.png',
  'platinum_2': 'assets/rank/platinium_2.png',
  'platinum_1': 'assets/rank/platinium_1.png',
  'master_3': 'assets/rank/master_3.png',
  'master_2': 'assets/rank/master_2.png',
  'master_1': 'assets/rank/master_1.png',
};

/// Resolves any incoming rank key to one of the 15 official rank assets.
/// Unknown keys safely fall back through [rankTierForKey] to Bronze III.
String rankAssetPath(String rankKey) {
  final normalizedKey = rankTierForKey(rankKey).key;
  return rankEmblemAssets[normalizedKey] ?? rankEmblemAssets['bronze_3']!;
}

/// Background-free competitive rank emblem backed by the official PNG set in
/// `assets/rank/`.
///
/// Rank surfaces should use this widget instead of drawing their own shield,
/// medal, league icon or division marker. This keeps profile, leaderboard,
/// matchmaking and result surfaces visually consistent as the rank art evolves.
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
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodedSize = (size * devicePixelRatio)
        .ceil()
        .clamp(64, 512)
        .toInt();

    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        rankAssetPath(tier.key),
        width: size,
        height: size,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        cacheWidth: decodedSize,
        cacheHeight: decodedSize,
        semanticLabel: semanticLabel ?? '${tier.label} rank emblem',
      ),
    );
  }
}
