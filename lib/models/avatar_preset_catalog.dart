class AvatarPreset {
  const AvatarPreset({
    required this.key,
    required this.label,
    required this.assetPath,
  });

  final String key;
  final String label;
  final String assetPath;
}

/// The only selectable avatar catalog in the app.
///
/// Every option maps directly to a PNG under `assets/avatar/`. There are no
/// generated icon presets, initials avatars, platform/Game Center/Play Games
/// avatar choices, remote images, or any other selectable avatar source.
class AvatarPresetCatalog {
  AvatarPresetCatalog._();

  static const int count = 40;
  static const String firstKey = 'preset_001';
  static const String firstAssetPath = 'assets/avatar/avatar.png';

  static final List<AvatarPreset> all = List<AvatarPreset>.unmodifiable(
    List<AvatarPreset>.generate(count, (index) {
      final number = index + 1;
      return AvatarPreset(
        key: 'preset_${number.toString().padLeft(3, '0')}',
        label: 'Avatar ${number.toString().padLeft(2, '0')}',
        assetPath: number == 1
            ? firstAssetPath
            : 'assets/avatar/avatar ($number).png',
      );
    }),
  );

  static AvatarPreset? byKey(String key) {
    if (!key.startsWith('preset_')) return null;
    final index = int.tryParse(key.substring('preset_'.length));
    if (index == null || index < 1 || index > all.length) return null;
    return all[index - 1];
  }

  /// Legacy/platform/default keys collapse to the first bundled avatar so old
  /// accounts never surface an avatar from outside `assets/avatar/`.
  static String normalizeKey(String key) => byKey(key)?.key ?? firstKey;

  static String assetPathForKey(String key) =>
      byKey(key)?.assetPath ?? firstAssetPath;
}
