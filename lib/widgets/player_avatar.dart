import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/avatar_preset_catalog.dart';
import '../models/rank_identity_models.dart';
import '../services/rank_identity_service.dart';
import 'rank_frame_overlay.dart';

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.displayName,
    this.avatarKey = AvatarPresetCatalog.firstKey,
    this.localAvatarBytes,
    this.remoteApprovedImageUrl,
    this.radius = 22,
    this.semanticLabel,
  });

  final String displayName;
  final String avatarKey;

  /// Kept only for source compatibility with older call sites. Platform/native
  /// avatar bytes are intentionally ignored: `assets/avatar/` is now the sole
  /// avatar image source.
  final Uint8List? localAvatarBytes;

  /// Kept only for source compatibility. Remote avatar URLs are intentionally
  /// ignored so a profile can never render an avatar outside `assets/avatar/`.
  final String? remoteApprovedImageUrl;

  final double radius;
  final String? semanticLabel;

  static void configureCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = cache.maximumSize.clamp(64, 128).toInt();
    cache.maximumSizeBytes = cache.maximumSizeBytes
        .clamp(16 * 1024 * 1024, 32 * 1024 * 1024)
        .toInt();
  }

  @override
  Widget build(BuildContext context) {
    configureCache();
    final label = semanticLabel ?? displayName;
    final size = radius * 2;
    final identity = RankIdentityKey.parse(avatarKey);
    final normalizedAvatarKey = _resolvedAssetAvatarKey(identity.avatarKey);
    final assetPath = AvatarPresetCatalog.assetPathForKey(normalizedAvatarKey);

    final image = Image.asset(
      assetPath,
      fit: BoxFit.cover,
      cacheWidth: size.round(),
      cacheHeight: size.round(),
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );

    return Semantics(
      image: true,
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: RankFrameOverlay(
          size: size,
          frameKey: identity.frameKey ?? 'bronze_3',
          decorationKeys: identity.decorationKeys,
          child: ClipOval(child: image),
        ),
      ),
    );
  }

  String _resolvedAssetAvatarKey(String baseKey) {
    final direct = AvatarPresetCatalog.byKey(baseKey);
    if (direct != null) return direct.key;

    // The home header historically uses an internal `professional-home-*` key.
    // Resolve that owner-local placeholder to the selected in-app avatar rather
    // than to Game Center / Play Games imagery.
    if (baseKey.startsWith('professional-home-') ||
        baseKey.startsWith('home-profile-')) {
      final selected = RankIdentityService.instance.current.value?.selectedAvatarKey;
      if (selected != null) return AvatarPresetCatalog.normalizeKey(selected);
    }

    return AvatarPresetCatalog.firstKey;
  }
}
