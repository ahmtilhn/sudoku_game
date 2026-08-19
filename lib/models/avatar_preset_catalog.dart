import 'package:flutter/material.dart';

class AvatarPreset {
  const AvatarPreset({
    required this.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Color accent;
}

/// A deliberately game-relevant, dependency-free avatar library.
///
/// The 96 presets are generated from 12 logic/strategy motifs and 8 restrained
/// palettes. Keeping these inside Flutter avoids third-party portrait licenses,
/// broken CDN links, tracking requests and unrelated stock photography.
class AvatarPresetCatalog {
  AvatarPresetCatalog._();

  static const List<_AvatarMotif> _motifs = <_AvatarMotif>[
    _AvatarMotif('Grid', Icons.grid_4x4_rounded),
    _AvatarMotif('Mind', Icons.psychology_rounded),
    _AvatarMotif('Piece', Icons.extension_rounded),
    _AvatarMotif('Logic', Icons.functions_rounded),
    _AvatarMotif('Numbers', Icons.calculate_rounded),
    _AvatarMotif('Core', Icons.memory_rounded),
    _AvatarMotif('Guardian', Icons.shield_rounded),
    _AvatarMotif('Spark', Icons.bolt_rounded),
    _AvatarMotif('Focus', Icons.auto_awesome_rounded),
    _AvatarMotif('Crystal', Icons.diamond_rounded),
    _AvatarMotif('Network', Icons.hub_rounded),
    _AvatarMotif('Hex', Icons.hexagon_rounded),
  ];

  static const List<_AvatarPalette> _palettes = <_AvatarPalette>[
    _AvatarPalette(Color(0xFF12232E), Color(0xFFE8F5FF), Color(0xFF5EC8FF)),
    _AvatarPalette(Color(0xFF1A2433), Color(0xFFF4F0FF), Color(0xFF9D8BFF)),
    _AvatarPalette(Color(0xFF102A24), Color(0xFFE9FFF8), Color(0xFF52D6A8)),
    _AvatarPalette(Color(0xFF332610), Color(0xFFFFF6D8), Color(0xFFFFC857)),
    _AvatarPalette(Color(0xFF301C23), Color(0xFFFFEEF3), Color(0xFFFF7A9E)),
    _AvatarPalette(Color(0xFF25212F), Color(0xFFFFF2FF), Color(0xFFD990FF)),
    _AvatarPalette(Color(0xFF2B211A), Color(0xFFFFF2E8), Color(0xFFD89563)),
    _AvatarPalette(Color(0xFF20282D), Color(0xFFF0F7FA), Color(0xFF9DB3BF)),
  ];

  static final List<AvatarPreset> all = List<AvatarPreset>.unmodifiable(
    List<AvatarPreset>.generate(96, (index) {
      final motif = _motifs[index % _motifs.length];
      final palette = _palettes[(index ~/ _motifs.length) % _palettes.length];
      final number = index + 1;
      return AvatarPreset(
        key: 'preset_${number.toString().padLeft(3, '0')}',
        label: '${motif.label} ${number.toString().padLeft(2, '0')}',
        icon: motif.icon,
        background: palette.background,
        foreground: palette.foreground,
        accent: palette.accent,
      );
    }),
  );

  static AvatarPreset? byKey(String key) {
    if (!key.startsWith('preset_')) return null;
    final index = int.tryParse(key.substring('preset_'.length));
    if (index == null || index < 1 || index > all.length) return null;
    return all[index - 1];
  }
}

class _AvatarMotif {
  const _AvatarMotif(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _AvatarPalette {
  const _AvatarPalette(this.background, this.foreground, this.accent);

  final Color background;
  final Color foreground;
  final Color accent;
}
