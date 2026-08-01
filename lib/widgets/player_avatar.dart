import 'dart:typed_data';

import 'package:flutter/material.dart';

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
    return Semantics(
      image: true,
      label: label,
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: _image(context, size) ?? _fallback(context),
        ),
      ),
    );
  }

  Widget? _image(BuildContext context, double size) {
    final bytes = localAvatarBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: size.round(),
        cacheHeight: size.round(),
        errorBuilder: (_, _, _) => _fallback(context),
        frameBuilder: _frameBuilder,
      );
    }

    final url = remoteApprovedImageUrl?.trim();
    if (url != null && url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: size.round(),
        cacheHeight: size.round(),
        errorBuilder: (_, _, _) => _fallback(context),
        frameBuilder: _frameBuilder,
      );
    }
    return null;
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
        _fallback(context),
        const Center(
          child: SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _initials(displayName);
    final seed = avatarKey.hashCode.abs();
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
