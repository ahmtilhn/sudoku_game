import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/avatar_preset_catalog.dart';
import '../models/rank_identity_models.dart';
import '../services/platform_game_services.dart';
import 'rank_frame_overlay.dart';

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.displayName,
    this.avatarKey = 'default',
    this.localAvatarBytes,
    this.remoteApprovedImageUrl,
    this.radius = 22,
    this.semanticLabel,
  });

  final String displayName;
  final String avatarKey;
  final Uint8List? localAvatarBytes;
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
    final baseKey = identity.avatarKey;
    final image = _image(context, size, baseKey) ??
        _presetAvatar(baseKey) ??
        _fallback(context, baseKey);
    final clipped = ClipOval(child: image);

    return Semantics(
      image: true,
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: RankFrameOverlay(
          size: size,
          // Legacy/default identities predate the RP system. They still begin
          // visually at the same public starting point: Bronze III / 0 RP.
          frameKey: identity.frameKey ?? 'bronze_3',
          decorationKeys: identity.decorationKeys,
          child: clipped,
        ),
      ),
    );
  }

  Widget? _image(BuildContext context, double size, String baseKey) {
    // Explicit presets must win over native platform bytes/URLs. Legacy/default
    // identities retain the previous platform-avatar behavior.
    if (!baseKey.startsWith('preset_')) {
      final bytes = localAvatarBytes;
      if (bytes != null && bytes.isNotEmpty) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          cacheWidth: size.round(),
          cacheHeight: size.round(),
          errorBuilder: (_, _, _) => _fallback(context, baseKey),
          frameBuilder: _frameBuilder,
        );
      }

      final url = _resolvedRemoteUrl(baseKey);
      if (url != null && url.startsWith('https://')) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: size.round(),
          cacheHeight: size.round(),
          errorBuilder: (_, _, _) => _fallback(context, baseKey),
          frameBuilder: _frameBuilder,
        );
      }
    }
    return null;
  }

  Widget? _presetAvatar(String baseKey) {
    final preset = AvatarPresetCatalog.byKey(baseKey);
    if (preset == null) return null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.25, -.35),
          radius: 1.15,
          colors: [
            preset.accent.withValues(alpha: .48),
            preset.background,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: const Alignment(.65, -.68),
            child: Container(
              width: radius * .28,
              height: radius * .28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: preset.accent.withValues(alpha: .72),
              ),
            ),
          ),
          Center(
            child: Icon(
              preset.icon,
              size: radius * 1.06,
              color: preset.foreground,
            ),
          ),
        ],
      ),
    );
  }

  String? _resolvedRemoteUrl(String baseKey) {
    final configuredUrl = remoteApprovedImageUrl?.trim();
    if (configuredUrl != null && configuredUrl.isNotEmpty) {
      return configuredUrl;
    }

    if (!baseKey.startsWith('home-profile-')) return null;
    final player = PlatformGameServices.instance.localPlayer.value;
    final playGamesUrl = player?.avatarUrl?.trim();
    if (playGamesUrl == null || playGamesUrl.isEmpty) return null;
    return playGamesUrl;
  }

  Widget _frameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded || frame != null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        _fallback(context, RankIdentityKey.parse(avatarKey).avatarKey),
        const Center(
          child: SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }

  Widget _fallback(BuildContext context, String baseKey) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _initials(displayName);
    final seed = baseKey.hashCode.abs();
    final colors = <Color>[
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      scheme.surfaceContainerHighest,
    ];
    final color = colors[seed % colors.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: Center(
        child: Text(
          initials,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: (radius * 0.62).clamp(11, 22),
          ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    final first = String.fromCharCode(parts.first.runes.first).toUpperCase();
    if (parts.length == 1) return first;
    return '$first${String.fromCharCode(parts.last.runes.first).toUpperCase()}';
  }
}
